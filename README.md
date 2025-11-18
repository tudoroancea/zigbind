# Zigbind

High-performance Python bindings for Zig with an ergonomic, type-safe API.

## Features

- **Zero-overhead bindings**: Compile-time code generation, no runtime overhead
- **Automatic type conversion**: Seamless conversion between Zig and Python types
- **Ergonomic API**: No boilerplate - just write Zig functions and expose them
- **Type-safe**: Compile-time type checking ensures correctness
- **Error handling**: Automatic Zig error → Python exception mapping
- **Native build system**: Uses Zig's build system, no CMake/Bazel needed
- **Modern Python**: Python 3.12+ with stable ABI support (planned)

**Philosophy**: Similar to nanobind - compact, fast, and opinionated. We prioritize developer experience and performance over maximum flexibility.

## Quick Example

```zig
const zb = @import("zigbind");

fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn divide(a: f64, b: f64) !f64 {
    if (b == 0) return error.ValueError;
    return a / b;
}

export fn PyInit_mymodule() callconv(.c) ?*zb.PyObject {
    const module = zb.createModule(.{
        .name = "mymodule",
        .doc = "My awesome Zig module",
    }) catch return null;

    zb.defineFunction(module, .{
        .name = "add",
        .func = add,
        .doc = "Add two integers",
    }) catch return null;

    zb.defineFunction(module, .{
        .name = "divide",
        .func = divide,
        .doc = "Divide two floats (raises ValueError if divisor is zero)",
    }) catch return null;

    return module;
}
```

That's it! No manual `PyMethodDef` arrays, no struct initialization, no type conversion boilerplate.

## Supported Types

| Zig Type | Python Type | Notes |
|----------|-------------|-------|
| `i32`, `i64`, etc. | `int` | Automatic overflow checking |
| `f32`, `f64` | `float` | Accepts Python ints too |
| `bool` | `bool` | Native boolean conversion |
| `[]const u8` | `str` | UTF-8 strings |
| `?T` | `T \| None` | Optional types |
| `!T` | Exception or `T` | Error unions |
| `void` | `None` | No return value |

## Installation & Usage

### Prerequisites

- Zig 0.15.x
- Python 3.12+
- `uv` (recommended) or `pip`

### Building an Extension

```bash
# Clone zigbind (or add as dependency in build.zig.zon)
git clone https://github.com/yourusername/zigbind.git

# Create your extension (see examples/hellozig)
cd examples/hellozig

# Build
zig build -Dpython_prefix=$(uv run --no-project python -c 'import sys; print(sys.base_prefix)')

# Run
PYTHONPATH=./zig-out/lib uv run --no-project python -c "import hellozig; print(hellozig.add(5, 3))"
# Output: 8
```

### Running Tests

```bash
cd zigbind
uv run pytest tests/ -v
```

All 22 tests should pass!

## Current Status

**✅ Iteration 1 Complete**: Ergonomic function bindings with automatic type conversion

- [x] Function bindings with automatic type inference
- [x] Basic type conversion (int, float, bool, string, optional)
- [x] Error handling (Zig errors → Python exceptions)
- [x] Comprehensive test suite
- [ ] Class/struct bindings (Iteration 2)
- [ ] Stable ABI configuration
- [ ] Lists, tuples, dicts
- [ ] NumPy interop
- [ ] Build backend for pip install

See [CHANGELOG.md](CHANGELOG.md) for detailed changes and [ZIGBIND_IMPLEMENTATION_PLAN.md](ZIGBIND_IMPLEMENTATION_PLAN.md) for the full roadmap.

## Contributing

This project is in active development. Contributions welcome!

## License

BSD-3-Clause
