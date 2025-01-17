{
  description = "ptags";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-24.11";
  };

  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in
    rec {
      packages.x86_64-linux.default = pkgs.buildEnv {
        name = "ptags-env";
        # TODO in theory should set env here so that uv never tries do manage a python version
        paths = with pkgs; [ uv python313 ];
      };
      # TODO setting ld library path can have downsides apparently (?)
      packages.x86_64-linux.app = pkgs.writeScriptBin "ptags" ''
        #!${pkgs.zsh}/bin/zsh
        set -eu -o pipefail
        args=(
          --python=${pkgs.python313}/bin/python
          --no-python-downloads
          --no-progress
          --project ${self}
          --locked
          # TODO this forces a fresh one? that's not what i want
          --isolated
          --no-editable
          --compile-bytecode
          --quiet
        )
        ${pkgs.uv}/bin/uv run $args -- python -Pm ptags $@
      '';
      packages.x86_64-linux.ts = pkgs.tree-sitter-grammars.tree-sitter-python;
      apps.x86_64-linux.default = {
        type = "app";
        program = "${packages.x86_64-linux.app}/bin/ptags";
      };
    };
}
