{
  description = "Rt: An overlay type system for shell pipelines";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix_hammer_overrides = {
      url = "github:TyberiusPrime/uv2nix_hammer_overrides";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    pyproject-nix,
    uv2nix,
    pyproject-build-systems,
    uv2nix_hammer_overrides,
    ...
  }: let
    inherit (nixpkgs) lib;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    forAllSystems = lib.genAttrs systems;

    workspace = uv2nix.lib.workspace.loadWorkspace {workspaceRoot = ./.;};

    overlay = workspace.mkPyprojectOverlay {
      sourcePreference = "wheel";
    };

    editableOverlay = workspace.mkEditablePyprojectOverlay {
      root = "$REPO_ROOT";
    };

    meta = {
      description = "An overlay type system for Unix shell pipelines";
      homepage = "https://github.com/atlas-brown/rt";
      license = lib.licenses.mit;
      mainProgram = "rt";
      platforms = lib.platforms.unix;
    };

    wrapRt = {
      pkgs,
      jdk,
      bin,
    }:
      pkgs.runCommand "rt-0.1.0" {
        nativeBuildInputs = [pkgs.makeWrapper];
        inherit meta;
      } ''
        mkdir -p "$out/bin"
        makeWrapper ${bin}/rt "$out/bin/rt" \
          --set JAVA_HOME ${jdk} \
          --prefix PATH : ${lib.makeBinPath [jdk]} \
          --set RT_AUTOMATON_JAR ${./jars/automaton.jar}
        makeWrapper ${bin}/rti "$out/bin/rti" \
          --set JAVA_HOME ${jdk} \
          --prefix PATH : ${lib.makeBinPath [jdk]} \
          --set RT_AUTOMATON_JAR ${./jars/automaton.jar}
      '';

    pythonSets = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        python = pkgs.python312;
        pyprojectOverrides = final: prev: {
          libdash = prev.libdash.overrideAttrs (old: {
            nativeBuildInputs =
              (old.nativeBuildInputs or [])
              ++ (with pkgs; [autoconf automake libtool])
              ++ final.resolveBuildSystem {setuptools = [];};
            env = (old.env or {}) // {CFLAGS = "-std=gnu17";};
            postPatch =
              (old.postPatch or "")
              + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
                substituteInPlace setup.py --replace-fail 'libtoolize = "glibtoolize"' 'libtoolize = "libtoolize"'
              '';
          });
        };
      in
        (pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        }).overrideScope (
          lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            overlay
            (uv2nix_hammer_overrides.overrides pkgs)
            pyprojectOverrides
          ]
        )
    );

    rtPackages = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        pythonSet = pythonSets.${system};
        venv = pythonSet.mkVirtualEnv "rt-env" workspace.deps.default;
      in
        wrapRt {
          inherit pkgs;
          jdk = pkgs.jdk21;
          bin = "${venv}/bin";
        }
    );
  in {
    packages = forAllSystems (system: {
      default = rtPackages.${system};
      rt = rtPackages.${system};
    });

    apps = forAllSystems (system: {
      default = {
        type = "app";
        program = "${rtPackages.${system}}/bin/rt";
      };
      rti = {
        type = "app";
        program = "${rtPackages.${system}}/bin/rti";
      };
    });

    devShells = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        jdk = pkgs.jdk21;
        editablePythonSet = pythonSets.${system}.overrideScope editableOverlay;
        virtualenv = editablePythonSet.mkVirtualEnv "rt-dev-env" workspace.deps.all;
      in {
        default = pkgs.mkShell {
          packages = [
            virtualenv
            pkgs.uv
            jdk
          ];
          env = {
            UV_NO_SYNC = "1";
            UV_PYTHON = editablePythonSet.python.interpreter;
            UV_PYTHON_DOWNLOADS = "never";
            JAVA_HOME = "${jdk}";
          };
          shellHook = ''
            unset PYTHONPATH
            export REPO_ROOT=$(git rev-parse --show-toplevel)
            export RT_AUTOMATON_JAR="$REPO_ROOT/jars/automaton.jar"
          '';
        };
      }
    );

    checks = forAllSystems (system: {
      rt = rtPackages.${system};
    });

    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
  };
}
