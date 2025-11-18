# Changelog

All notable changes to zigbind will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added - Iteration 1: Ergonomic Function Bindings (2025-01-18)

#### Core Infrastructure
- **Type Conversion System** (`src/type_caster.zig`)
  - Generic `TypeCaster(T)` for bidirectional Zig ↔ Python conversion
  - Support for primitive types: `i32`, `i64`, `f32`, `f64`, `bool`
  - String conversion: `[]const u8` ↔ Python `str`
  - Optional type handling: `?T` ↔ Python `None`
  - Automatic type inference and conversion

- **Error Handling** (`src/errors.zig`)
  - Zig error → Python exception mapping
  - Support for `TypeError`, `ValueError`, `MemoryError`, `OverflowError`
  - Automatic error propagation from Zig functions
  - Custom error messages

- **Ergonomic Module API** (`src/module.zig`)
  - `createModule(config)` with struct-based configuration
  - Simplified module creation (no manual `PyModuleDef` initialization)
  - Helper functions for adding objects and constants

- **Ergonomic Function API** (`src/function.zig`)
  - `defineFunction(module, config)` - automatic function wrapping
  - Compile-time function signature introspection
  - Automatic argument parsing from Python tuples
  - Automatic return value conversion
  - Support for both error unions and regular returns
  - No manual `PyMethodDef` arrays needed

#### Developer Experience
- **Unified Python C API Import** (`src/python_api.zig`)
  - Single source of truth for Python C API types
  - Eliminates type mismatches between modules
  - Zig 0.15 compatibility fixes

- **Updated Example** (`examples/hellozig`)
  - Demonstrates new ergonomic API
  - Multiple function signatures: no args, int params, float params, string params, bool returns
  - Error handling examples
  - ~85% reduction in boilerplate code

#### Testing
- **Comprehensive Test Suite** (`tests/test_functions.py`)
  - 22 tests covering all basic types
  - Type conversion edge cases
  - Error handling verification
  - Type error validation
  - 100% pass rate

### Technical Details

- **Zig Version**: 0.15.x compatibility
  - Updated typeInfo field names (`.Fn` → `.@"fn"`, `.Int` → `.int`, etc.)
  - Updated calling convention (`.C` → `.c`)
  - Updated pointer size enum (`.Slice` → `.slice`)

- **Python Version**: 3.12+
  - Using `PyBool_FromLong` instead of `Py_True`/`Py_False` for better compatibility

### Removed
- Legacy `legacyModule()` function (superseded by `createModule()`)
- Experimental `zigbind.old.zig` file

---

## [0.0.1] - Initial Proof of Concept

### Added
- Basic Python C API bindings via `@cImport`
- Minimal module creation support
- Simple build system integration
- Hello world example
