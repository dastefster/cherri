// ===================================
// Cherri Bind Package
// v0.0.1 BUILD 2026-10-15 01:55
// The only package gomobile binds, so Swift sees Compile and CompilerVersion and none of the compiler's internals.
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
