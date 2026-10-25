// ===================================
// Cherri Bind Package
// v0.0.3 BUILD 2026-10-25 04:15
// The only package gomobile binds, so Swift sees Compile, Decompile, CompilerVersion and ActionCatalog and none of the compiler's internals.
// dev by @dastefster 🍒🔨
// ===================================

package cherri

import "cherrilib"

// ===================================
// EXPORTS
// ===================================

// gobind tries to wrap every exported name in the package it is given, and the compiler exports internal constants
// it can't convert, so the compiler stays behind this thin layer.
func Compile(source string, name string) ([]byte, error) {
	return cherrilib.Compile(source, name)
}

func CompilerVersion() string {
	return cherrilib.CompilerVersion()
}

// ActionCatalog returns every standard action with its parameters as a JSON string for the action picker.
func ActionCatalog() (string, error) {
	return cherrilib.ActionCatalog()
}

// Decompile turns an unsigned Shortcut plist back into Cherri source for the import feature.
func Decompile(shortcut []byte, name string) (string, error) {
	return cherrilib.Decompile(shortcut, name)
}
