inputs: system:
# This devShell uses uv2nix to construct a virtual environment purely from Nix, using the same dependency specification as the application.
# The notable difference is that we also apply another overlay here enabling editable mode ( https://setuptools.pypa.io/en/latest/userguide/development_mode.html ).
#
# This means that any changes done to your local files do not require a rebuild.
#
# Note: Editable package support is still unstable and subject to change.
let
  # Create an overlay enabling editable mode for all local dependencies.
  editableOverlay = workspace.mkEditablePyprojectOverlay {
    # Use environment variable
    root = "$REPO_ROOT";
    # Optional: Only enable editable for these packages
    # members = [ "hello-world" ];
  };

  # Override previous set with our overrideable overlay.
  editablePythonSet = pythonSet.overrideScope (
    lib.composeManyExtensions [
      editableOverlay

      # Apply fixups for building an editable package of your workspace packages
      (final: prev: {
        hello-world = prev.hello-world.overrideAttrs (old: {
          # It's a good idea to filter the sources going into an editable build
          # so the editable package doesn't have to be rebuilt on every change.
          src = lib.fileset.toSource {
            root = old.src;
            fileset = lib.fileset.unions [
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

