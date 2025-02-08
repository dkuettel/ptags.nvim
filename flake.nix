{
  description = "ptags";

  # see https://pyproject-nix.github.io/uv2nix/usage/hello-world.html

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

    # see https://github.com/numtide/flake-utils
    flake-utils.url = "github:numtide/flake-utils";

  };

  outputs = inputs:
    let
      flake = inputs.flake-utils.lib.eachDefaultSystem outputs;

      outputs = system:
        let
          outputs = {
            packages = {
              default = app;
              app = app;
              venv = venv;
              dev = dev;
            };
            apps.default = { type = "app"; program = "${venv}/bin/ptags"; };
            devShells = {
              # TODO they didnt quite totally work for me
              # This example provides two different modes of development:
              # - Impurely using uv to manage virtual environments
              # - Pure development using uv2nix to manage virtual environments
              impure = shellImpure;
              uv2nix = shellUv2nix;
            };
          };

          pkgs = inputs.nixpkgs.legacyPackages.${system};

          python = pkgs.python313; # TODO should that not come from the pyproject.toml?

          venv = pythonSet.mkVirtualEnv "ptags-env" workspace.deps.default;

          venvDev = editablePythonSet.mkVirtualEnv "ptags-dev-env" workspace.deps.all;

          app = (pkgs.callPackages inputs.pyproject-nix.build.util { }).mkApplication {
            venv = venv;
            package = pythonSet.ptags;
          };

          dev = pkgs.buildEnv {
            name = "dev";
            paths = [ python ] ++ (with pkgs; [ uv ruff basedpyright ]);
          };

          shellImpure = pkgs.mkShell {
            packages = [ python pkgs.uv ];
            env = {
              UV_PYTHON_DOWNLOADS = "never";
              UV_PYTHON = python.interpreter;
            } // inputs.nixpkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
              # Python libraries often load native shared objects using dlopen(3).
              # Setting LD_LIBRARY_PATH makes the dynamic library loader aware of libraries without using RPATH for lookup.
              LD_LIBRARY_PATH = inputs.nixpkgs.lib.makeLibraryPath pkgs.pythonManylinuxPackages.manylinux1;
            };
            shellHook = ''
              unset PYTHONPATH
            '';
          };

          shellUv2nix = pkgs.mkShell {
            packages = [ venvDev pkgs.uv ];
            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON = "${venvDev}/bin/python";
              UV_PYTHON_DOWNLOADS = "never";
            };
            shellHook = ''
              unset PYTHONPATH
              export REPO_ROOT=$(git rev-parse --show-toplevel)
            '';
          };

          pythonSet =
            (pkgs.callPackage inputs.pyproject-nix.build.packages {
              inherit python;
            }).overrideScope
              (
                inputs.nixpkgs.lib.composeManyExtensions [
                  inputs.pyproject-build-systems.overlays.default
                  overlay
                  pyprojectOverrides
                ]
              );

          workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

          overlay = workspace.mkPyprojectOverlay {
            sourcePreference = "wheel";
          };

          # see https://pyproject-nix.github.io/uv2nix/FAQ.html
          pyprojectOverrides = _final: _prev: {
            # see https://pyproject-nix.github.io/pyproject.nix/build.html
          };

          editableOverlay = workspace.mkEditablePyprojectOverlay {
            root = "$REPO_ROOT";
          };

          editablePythonSet = pythonSet.overrideScope (
            inputs.nixpkgs.lib.composeManyExtensions [
              editableOverlay
              (final: prev: {
                hello-world = prev.hello-world.overrideAttrs (old: {
                  # It's a good idea to filter the sources going into an editable build
                  # so the editable package doesn't have to be rebuilt on every change.
                  src = inputs.nixpkgs.lib.fileset.toSource {
                    root = old.src;
                    fileset = inputs.nixpkgs.lib.fileset.unions [
                      (old.src + "/pyproject.toml")
                      (old.src + "/README.md")
                      (old.src + "/src/ptags.py")
                    ];
                  };
                  # Hatchling (our build system) has a dependency on the `editables` package when building editables.
                  #
                  # In normal Python flows this dependency is dynamically handled, and doesn't need to be explicitly declared.
                  # This behaviour is documented in PEP-660.
                  #
                  # With Nix the dependency needs to be explicitly declared.
                  nativeBuildInputs =
                    old.nativeBuildInputs
                    ++ final.resolveBuildSystem {
                      editables = [ ];
                    };
                });
              })
            ]
          );

        in
        outputs;

    in
    flake;
}
