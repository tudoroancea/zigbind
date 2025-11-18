# Zigbind Agent Instructions

## Project Objective

See @README.md for information.

## Tech Stack

### Core
- **Zig 0.15.x**: Primary implementation language, build system
- **Python 3.12+**: Target runtime, using Limited API (Stable ABI)
- **Python C API**: Limited API subset for forward compatibility

### Development Tools
- **uv**: Python package/environment management
- **pytest**: Testing framework
- **ruff**: Python linting and formatting (replaces black, isort, flake8)
- **zig build**: Native build system (no external build tools needed)

## Resources

- [Python C API](https://docs.python.org/3/c-api/extension-modules.html)
- [Python C API stability](https://docs.python.org/3/c-api/stable.html)
- [Zig language reference](https://ziglang.org/documentation/master/)
- [Zig standard library](https://ziglang.org/documentation/master/std/)
- [Zig Build System](https://ziglang.org/learn/build-system/)
- [nanobind (inspiration)](https://github.com/wjakob/nanobind)
- [PEP 517 (Build Backend)](https://peps.python.org/pep-0517/)

---

*This file should be updated as the project evolves. Keep it accurate and concise.*
