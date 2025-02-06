inputs: system:
let
  venv = import ./venv.nix inputs system;
in
{
  type = "app";
  program = "${venv}/bin/ptags";
}
