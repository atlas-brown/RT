{
  description = "Rt: An overlay type system for shell pipelines";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
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

    perSystem = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      python = pkgs.python312;
      jdk = pkgs.jdk21;
    in {inherit pkgs python jdk;});

    otherPythonPackages = {
      pkgs,
      python,
    }: let
      inherit (python.pkgs) buildPythonPackage fetchPypi;
    in rec {
      libdash = buildPythonPackage rec {
        pname = "libdash";
        version = "0.4.1";
        pyproject = true;
        src = fetchPypi {
          inherit pname version;
          hash = "sha256-c1g4RJn3zpyf2OB5BOZVlFEHteXuv/SQZR361iSRwXU=";
        };
        build-system = [python.pkgs.setuptools];
        nativeBuildInputs = with pkgs; [autoconf automake libtool];
        # clang
        env.CFLAGS = "-std=gnu17";
        postPatch = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
          substituteInPlace setup.py --replace-fail 'libtoolize = "glibtoolize"' 'libtoolize = "libtoolize"'
        '';
      };

    pash-annotations = buildPythonPackage rec {
        pname = "pash-annotations";
        version = "0.2.4";
        format = "wheel";
        src = fetchPypi {
          pname = "pash_annotations";
          inherit version;
          format = "wheel";
          python = "py3";
          abi = "none";
          platform = "any";
          hash = "sha256-/0dab4EzOTM3t+HFpjloGeCDLB4mAcM0T5BcwsbUh9I=";
        };
      };

      shasta = buildPythonPackage rec {
        pname = "shasta";
        version = "0.5";
        pyproject = true;
        src = pkgs.fetchFromGitHub {
          owner = "binpash";
          repo = "shasta";
          rev = "3ec173d6dc96e9007f5b582634f9315eafcac867";
          hash = "sha256-royjA/t/KZLg8ouFWKyFCiuBKlMDlmBJ9nuXvGqZDbc=";
        };
        build-system = [python.pkgs.setuptools];
      };
    };

    rtPackages = forAllSystems (
      system: let
        inherit (perSystem.${system}) pkgs python jdk;
        inherit (python.pkgs) buildPythonApplication;
        inherit (otherPythonPackages {inherit pkgs python;}) libdash pash-annotations shasta;
      in
        buildPythonApplication {
          pname = "rt";
          version = "0.1.0";
          pyproject = true;
          src = lib.cleanSource ./.;
          build-system = [python.pkgs.uv-build];
          dependencies = [
            python.pkgs.jpype1
            python.pkgs.pyyaml
            python.pkgs.platformdirs
            libdash
            pash-annotations
            shasta
          ];
          pythonRelaxDeps = ["jpype1"];
          makeWrapperArgs = [
            "--set" "JAVA_HOME" "${jdk}"
            "--prefix" "PATH" ":" "${lib.makeBinPath [jdk]}"
            "--set" "RT_AUTOMATON_JAR" "${./jars/automaton.jar}"
          ];
          meta = {
            description = "An overlay type system for Unix shell pipelines";
            homepage = "https://github.com/atlas-brown/rt";
            license = {
              deprecated = false;
              spdxId = "MIT";
              fullName = "MIT License";
            };
            maintainers = [
              {
                email = "atlas@brown.edu";
                github = "atlas-brown";
                name = "Atlas Group";
              }
            ];
            mainProgram = "rt";
            platforms = lib.platforms.unix;
          };
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

    devShells = forAllSystems (system: let
      inherit (perSystem.${system}) pkgs python jdk;
    in {
      default = pkgs.mkShell {
        packages = [
          python
          pkgs.uv
          jdk
        ];
        JAVA_HOME = "${jdk}";
        env = {
            UV_NO_SYNC = "1";
            UV_PYTHON_DOWNLOADS = "never";
        };
        shellHook = ''
          unset PYTHONPATH
        '';
      };
    });

    checks = forAllSystems (system: {
      rt = rtPackages.${system};
    });

    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
  };
}
