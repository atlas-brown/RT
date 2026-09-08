{
  description = "Rt: An overlay type system for shell pipelines";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {nixpkgs, ...}: let
    inherit (nixpkgs) lib;
    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    forAllSystems = lib.genAttrs systems;

    rtPackages = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        python = pkgs.python312;
        inherit (python.pkgs) buildPythonPackage buildPythonApplication fetchPypi;

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

        jdk = pkgs.jdk21;
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
            "--set JAVA_HOME ${jdk}"
            "--prefix PATH : ${lib.makeBinPath [jdk]}"
            "--set RT_AUTOMATON_JAR ${./jars/automaton.jar}"
          ];
          meta = {
            description = "An overlay type system for Unix shell pipelines";
            mainProgram = "rt";
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
  };
}
