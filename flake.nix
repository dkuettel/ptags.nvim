{
  description = "ptags";

  # see https://pyproject-nix.github.io/uv2nix/usage/hello-world.html

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";

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
            # > nix build .#name
            packages = {
              default = dev;
              dev = dev;
              app = app; # NOTE app doesnt leak the python paths
            };
            # > nix run .#name
            apps.default = { type = "app"; program = "${app}/bin/ptags"; };
          };

          pkgs = inputs.nixpkgs.legacyPackages.${system};

          python-version = pkgs.lib.strings.fileContents ./.python-version;
          python-package = "python${pkgs.lib.strings.concatStrings (pkgs.lib.strings.splitString "." python-version)}";
          python = pkgs.${python-package};

          venv = pythonSet.mkVirtualEnv "ptags-env" workspace.deps.default;

          app = (pkgs.callPackages inputs.pyproject-nix.build.util { }).mkApplication {
            venv = venv;
            package = pythonSet.ptags;
          };

          uv = pkgs.writeScriptBin "uv" ''
            #!${pkgs.zsh}/bin/zsh
            set -eu -o pipefail
            UV_PYTHON=${python}/bin/python ${pkgs.uv}/bin/uv --no-python-downloads $@
          '';

          dev = pkgs.buildEnv {
            name = "dev";
            paths = [ uv python ] ++ (with pkgs; [
              ruff
              basedpyright
              lua-language-server
              stylua
            ]);
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
            # pprofile = prev.pprofile.overrideAttrs (old:
            #   { nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ (final.resolveBuildSystem { setuptools = [ ]; }); }
            # );
          };

        in
        outputs;

    in
    flake;
}
