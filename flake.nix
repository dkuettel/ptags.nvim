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
      build = system: {
        packages.default = import ./venv.nix inputs system;
        apps.default = import ./app.nix inputs system;
        # This example provides two different modes of development:
        # - Impurely using uv to manage virtual environments
        # - Pure development using uv2nix to manage virtual environments
        devShells.impure = import ./impure-shell.nix inputs system;
        devShells.uv2nix = import ./uv2nix-shell.nix inputs system;
      };
    in
    inputs.flake-utils.lib.eachDefaultSystem build;
}
