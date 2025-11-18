# Zigbind

This library aims at providing a way to create Python bindings to Zig code with:
- Zero-overhead Python bindings for Zig code
- Native Zig build system integration (no CMake/Bazel)
- Stable ABI support (Python 3.12+)
- Compile-time metaprogramming via Zig's `comptime`
- Explicit error handling bridging Zig errors to Python exceptions

**Philosophy**: Similar to nanobind - compact, fast, and opinionated. We prioritize developer experience and performance over maximum flexibility.

## Quickstart

```bash
# build python bindings from zig code
zig build -Dpython_prefix=$(uv run --no-project python -c 'import sys; print(sys.base_prefix)')
# call the bindings from a python script
PYTHONPATH=./zig-out/lib uv run --no-project demo.py
```
