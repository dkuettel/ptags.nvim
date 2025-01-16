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
        LD_LIBRARY_PATH=/run/opengl-driver/lib ${pkgs.uv}/bin/uv run --python=${pkgs.python313}/bin/python --no-python-downloads --project ${self} --isolated --quiet python $@
      '';
      apps.x86_64-linux.default = {
        type = "app";
        program = "${packages.x86_64-linux.app}/bin/ptags";
      };
    };
}
