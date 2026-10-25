# Patches to the Cherri compiler

`cherri-src/` is a local clone of upstream Cherri and is gitignored here, so changes made inside it live
only on one machine. Each patch below is kept so a fresh clone can be brought back to the shipped state:

    cd cherri-src && git apply ../patches/0001-decompile-scriptable-and-variable-outputs.patch

- 0001: decompile the two Scriptable Run actions (their script/texts/urls have no plist keys, so import
  dropped them), and let an action output of type `variable` fit any parameter type (imported shortcuts
  feed such outputs straight into text arguments, which the compiler used to reject).
