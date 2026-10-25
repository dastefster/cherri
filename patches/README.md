# Patches to the Cherri compiler

`cherri-src/` is a local clone of upstream Cherri and is gitignored here, so changes made inside it live
only on one machine. Each patch below is kept so a fresh clone can be brought back to the shipped state:

    cd cherri-src && git apply ../patches/0001-decompile-scriptable-and-variable-outputs.patch

- 0001: decompile the two Scriptable Run actions (their script/texts/urls have no plist keys, so import
  dropped them), and let an action output of type `variable` fit any parameter type (imported shortcuts
  feed such outputs straight into text arguments, which the compiler used to reject).
  Also fixes Text actions being escaped twice on decompile (every quote became \\" and the code would not parse).
  Later additions in the same patch: Set Variable keeps its input on decompile, positional arguments stay aligned
  when a parameter is absent, `prompt.multiline` is a bool, references inside text (If result, Repeat Index/Item)
  are registered (the `Value` struct read `attachmentsByRange` with the wrong plist key), If/Menu results are matched
  by GroupingIdentifier instead of position, and a branch's last Text action is kept as its result.
  Also: `const x = rawAction(...)` and `@x = rawAction(...)` kept the generic raw action identifier (only a bare call
  applied the override), `AppIntentDescriptor` stays a plain dictionary through decompile/compile (Apple's own
  `shortcuts sign` crashes on a string there), and rawAction decompile no longer drops parameters when an action has
  both a UUID and an output name.
