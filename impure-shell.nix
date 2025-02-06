inputs: system:
let
  inherit (inputs.nixpkgs) lib;
  pkgs = inputs.nixpkgs.legacySystem.${system};
in
# It is of course perfectly OK to keep using an impure virtualenv workflow and only use uv2nix to build packages.
  # This devShell simply adds Python and undoes the dependency leakage done by Nixpkgs Python infrastructure.
pkgs.mkShell {
  packages = [
    (import ./python.nix pkgs)
    pkgs.uv
  ];
  env =
    {
      # Prevent uv from managing Python downloads
      UV_PYTHON_DOWNLOADS = "never";
      # Force uv to use nixpkgs Python interpreter
      UV_PYTHON = python.interpreter;
    }
    // lib.optionalAttrs pkgs.stdenv.isLinux {
      # Python libraries often load native shared objects using dlopen(3).
      # Setting LD_LIBRARY_PATH makes the dynamic library loader aware of libraries without using RPATH for lookup.
      LD_LIBRARY_PATH = lib.makeLibraryPath pkgs.pythonManylinuxPackages.manylinux1;
    };
  shellHook = ''
    unset PYTHONPATH
  '';
}
