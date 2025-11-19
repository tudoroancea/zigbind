# Zigbind

High-performance Python bindings for Zig with an ergonomic, type-safe API.

## Features

- **Zero-overhead bindings**: Compile-time code generation, no runtime overhead
- **Automatic type conversion**: Seamless conversion between Zig and Python types
- **Ergonomic API**: Minimal boilerplate - just write Zig functions and expose them
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
    var module = zb.Module.init(.{
        .name = "mymodule",
        .doc = "My awesome Zig module",
    }) catch return null;

    module.def(.{ .name = "add", .func = add, .doc = "Add two integers" }) catch return null;
    module.def(.{ .name = "divide", .func = divide, .doc = "Divide two floats (raises ValueError if divisor is zero)" }) catch return null;

    return module.pyobject();
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
| `[]T` (slices) | `list[T]` | Dynamic lists with proper memory management |
| `?T` | `T \| None` | Optional types |
| `!T` | Exception or `T` | Error unions |
| `void` | `None` | No return value |

## Prerequisites

- Zig 0.15.x
- Python 3.12+

## Using Zigbind in Your Project

Add zigbind as a dependency using `zig fetch`:

```bash
zig fetch --save https://github.com/tudoroancea/zigbind/archive/refs/heads/main.tar.gz
```

For local development, you can also use a relative path in `build.zig.zon`:

```zon
.dependencies = .{
    .zigbind = .{
        .path = "../zigbind",
    },
}
```

Then import and use in `build.zig`:

```zig
const zb = b.dependency("zigbind", .{});
const mymodule = b.addSharedLibrary(.{
    .name = "mymodule",
    .root_source_file = b.path("src/mymodule.zig"),
    .target = target,
    .optimize = optimize,
});
mymodule.root_module.addImport("zigbind", zb.module("zigbind"));
```

## Examples

We provide working examples demonstrating different features:

### hellozig
Basic "Hello, World!" style example showing minimal setup.

### types_demo
Comprehensive demo covering:
- Integer, float, and boolean types
- String handling (UTF-8)
- Error handling (Zig errors → Python exceptions)
- Basic function binding patterns

To run an example:

```bash
cd examples/types_demo
zig build -Dpython_prefix=$(python3 -c "import sys; print(sys.base_prefix)")
PYTHONPATH=./zig-out/lib python3 << 'EOF'
import types_demo
print(types_demo.add(5, 3))              # 8
print(types_demo.multiply(2.5, 4.0))     # 10.0
print(types_demo.is_positive(-5))        # False
print(types_demo.greet("Zig"))           # Zig
try:
    types_demo.divide(10.0, 0.0)
except ValueError:
    print("Division by zero caught")
EOF
```

## Current Status

**✅ Iteration 2 In Progress**: Container type support

### Completed
- [x] Function bindings with automatic type inference
- [x] Basic type conversion (int, float, bool, string, optional, error unions)
- [x] Error handling (Zig errors → Python exceptions)
- [x] **List support** (`[]T ↔ list[T]`) with proper memory management
- [x] Memory leak fixes with pytest-dependency integration
- [x] Comprehensive test suite (57 tests)

### Planned
- [ ] Tuple support (`{T1, T2, ...} ↔ tuple[T1, T2, ...]`)
- [ ] Dict support (`HashMap(K, V) ↔ dict[K, V]`)
- [ ] Set support (`HashSet(T) ↔ set[T]`)
- [ ] Class/struct bindings
- [ ] Stable ABI configuration
- [ ] NumPy interop
- [ ] Build backend for pip install

See [CHANGELOG.md](CHANGELOG.md) for detailed changes and [ZIGBIND_IMPLEMENTATION_PLAN.md](ZIGBIND_IMPLEMENTATION_PLAN.md) for the full roadmap.

## Contributing

This project is in active development. Contributions welcome!

## License

BSD-3-Clause
