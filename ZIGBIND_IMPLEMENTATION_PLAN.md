# Zigbind Implementation Plan
## High-Performance Python Bindings for Zig

**Version:** 1.0  
**Target:** Zig 0.15.*, Python 3.12+  
**ABI:** Stable ABI (PY_LIMITED_API = 0x030C0000)

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Technical Constraints](#technical-constraints)
3. [Phase 0: Project Bootstrap](#phase-0-project-bootstrap-week-1)
4. [Phase 1: Core Architecture](#phase-1-core-architecture-weeks-2-3)
5. [Phase 2: Build Backend](#phase-2-build-backend-weeks-4-5)
6. [Phase 3: Basic Bindings](#phase-3-basic-bindings-weeks-6-8)
7. [Phase 4: Type System](#phase-4-type-system-weeks-9-11)
8. [Phase 5: Advanced Features](#phase-5-advanced-features-weeks-12-15)
9. [Phase 6: Stub Generation](#phase-6-stub-generation-weeks-16-17)
10. [Phase 7: Testing & CI](#phase-7-testing--ci-weeks-18-19)
11. [Phase 8: Documentation](#phase-8-documentation-week-20)
12. [Phase 9: Polish & Release](#phase-9-polish--release-weeks-21-22)
13. [Appendices](#appendices)

---

## Project Overview

### Goal
Create a high-performance Python binding library for Zig that mirrors nanobind's philosophy: compact, fast, and opinionated. Unlike nanobind/pybind11, zigbind uses Zig's native build system and leverages compile-time metaprogramming for zero-overhead abstractions.

### Key Differentiators
- **Zig Build System**: Native integration, no CMake/Bazel complexity
- **Compile-time Metaprogramming**: Use `comptime` for type introspection and code generation
- **Explicit Error Handling**: Bridge Zig's error sets to Python exceptions
- **Stable ABI**: Forward-compatible wheels for Python 3.12+
- **Zero Dependencies**: Pure Zig + Python C API (Limited API)

---

## Technical Constraints

### Stable ABI Requirements

The Limited API requires defining `Py_LIMITED_API` to `0x030C0000` for Python 3.12, which enables building extension modules that work across Python versions without recompilation but with some performance penalty.

**Implementation Details:**
- Define `Py_LIMITED_API=0x030C0000` when compiling C code
- Link against `python3.dll` (Windows) or `libpython3.so` (Unix), NOT version-specific libraries
- Use `.abi3.so` suffix on Unix, `.abi3.pyd` on Windows
- Python 3.12+ includes vectorcall in Limited API, reducing performance penalty
- Cannot access internal struct layouts (e.g., `PyObject_HEAD` expansion)
- All API calls go through function pointers, not macros

**Challenges:**
1. **Performance**: ~10-20% overhead vs full API (acceptable for function dispatch)
2. **Type Introspection**: Must use heap-allocated types (`PyType_FromSpec`) instead of static types
3. **Object Layout**: Cannot co-locate instance data directly in `PyObject` without careful design
4. **Reference Counting**: More indirect, need careful management

**Solutions:**
- Use `PyType_Spec` for all type definitions
- Implement custom allocators that store Zig instance data after `PyObject` header
- Profile hot paths and optimize accordingly
- Document performance characteristics

### Zig 0.15.* Specifics

**Build System:**
- Use `std.Build` API (stable as of 0.13)
- `addSharedLibrary()` for creating extension modules
- `linkSystemLibrary("python3")` for Python linkage
- Support for `-dynamic` flag to create shared libraries

**Language Features to Leverage:**
- `comptime` for type introspection and code generation
- Generic types for type casters
- Error sets for exception mapping
- Optional types for None handling
- Tagged unions for variant types
- Allocators for memory management

---

## Phase 0: Project Bootstrap (Week 1)

### Objective
Create a minimal, working project structure that can build a "hello world" extension module and be installed via pip from day one.

### 0.1: Directory Structure

```
zigbind/
├── pyproject.toml                 # PEP 517 build config
├── README.md
├── LICENSE (BSD-3-Clause)
├── build.zig.zon                  # Zig package manifest
├── _backend/                      # In-tree PEP 517 backend
│   └── backend.py                 # Custom build backend
├── src/
│   ├── zigbind.zig               # Main library entry point
│   ├── core/                     # Core C code for Limited API
│   │   ├── module.c              # PyModuleDef implementation
│   │   ├── type.c                # PyType_Spec helpers
│   │   ├── function.c            # Function dispatch
│   │   └── common.h              # Shared definitions
│   ├── module.zig                # Zig module API
│   ├── types.zig                 # Type registration
│   ├── function.zig              # Function binding
│   └── build_support.zig         # Build system helpers
├── examples/
│   └── hello_world/              # Minimal example
│       ├── pyproject.toml
│       ├── build.zig
│       └── src/
│           ├── hello.zig         # Extension implementation
│           └── hello_py/         # Python package
│               └── __init__.py
└── tests/
    ├── conftest.py               # Pytest configuration
    └── test_core.py              # Basic tests
```

### 0.2: Minimal pyproject.toml

```toml
[build-system]
requires = ["wheel", "setuptools"]
build-backend = "_backend.backend"
backend-path = ["_backend"]

[project]
name = "zigbind"
version = "0.1.0"
description = "Fast Python bindings for Zig"
readme = "README.md"
requires-python = ">=3.12"
license = {text = "BSD-3-Clause"}
authors = [{name = "Your Name", email = "your.email@example.com"}]
classifiers = [
    "Development Status :: 3 - Alpha",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: BSD License",
    "Programming Language :: Python :: 3.12",
    "Programming Language :: Python :: 3.13",
    "Programming Language :: Zig",
]

[project.urls]
Homepage = "https://github.com/yourusername/zigbind"
Documentation = "https://zigbind.readthedocs.io"
Repository = "https://github.com/yourusername/zigbind"

[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
```

### 0.3: PEP 517 Build Backend

Create `_backend/backend.py`:

```python
"""
Zigbind PEP 517 build backend
Wraps 'zig build' to create Python extension modules
"""
import os
import sys
import subprocess
import tempfile
import shutil
from pathlib import Path
from wheel.wheelfile import WheelFile
import sysconfig

def build_wheel(wheel_directory, config_settings=None, metadata_directory=None):
    """Build a wheel for this extension module."""
    
    # Parse config settings
    config_settings = config_settings or {}
    zig_args = config_settings.get('zig-args', '').split()
    
    # Run zig build
    build_dir = Path('zig-out')
    subprocess.run(
        ['zig', 'build', '--release=fast'] + zig_args,
        check=True,
    )
    
    # Find the built extension
    ext_suffix = sysconfig.get_config_var('EXT_SUFFIX')
    if ext_suffix is None:
        # Stable ABI: use .abi3.so/.abi3.pyd
        if sys.platform == 'win32':
            ext_suffix = '.abi3.pyd'
        else:
            ext_suffix = '.abi3.so'
    
    # Create wheel
    wheel_path = _create_wheel(wheel_directory, build_dir, ext_suffix)
    
    return Path(wheel_path).name

def build_sdist(sdist_directory, config_settings=None):
    """Build a source distribution."""
    
    # Create tarball with all source files
    import tarfile
    
    version = _get_version()
    sdist_name = f"zigbind-{version}.tar.gz"
    sdist_path = Path(sdist_directory) / sdist_name
    
    with tarfile.open(sdist_path, 'w:gz') as tar:
        for item in ['src', 'pyproject.toml', 'build.zig', 'build.zig.zon', 
                     'README.md', 'LICENSE', '_backend']:
            if Path(item).exists():
                tar.add(item)
    
    return sdist_name

def get_requires_for_build_wheel(config_settings=None):
    """Return list of requirements for building wheel."""
    return ["wheel", "setuptools"]

def get_requires_for_build_sdist(config_settings=None):
    """Return list of requirements for building sdist."""
    return ["setuptools"]

def _get_version():
    """Extract version from pyproject.toml."""
    import tomllib  # Python 3.11+
    with open('pyproject.toml', 'rb') as f:
        data = tomllib.load(f)
    return data['project']['version']

def _create_wheel(wheel_dir, build_dir, ext_suffix):
    """Create wheel file from built artifacts."""
    from wheel.wheelfile import WheelFile
    
    # Determine wheel name
    version = _get_version()
    python_tag = 'cp312'  # For stable ABI
    abi_tag = 'abi3'
    platform_tag = _get_platform_tag()
    
    wheel_name = f"zigbind-{version}-{python_tag}-{abi_tag}-{platform_tag}.whl"
    wheel_path = Path(wheel_dir) / wheel_name
    
    with WheelFile(wheel_path, 'w') as wf:
        # Add extension module
        for ext_file in build_dir.rglob(f'*{ext_suffix}'):
            arcname = f"zigbind/{ext_file.name}"
            wf.write(ext_file, arcname)
        
        # Add Python stub file if exists
        stub_file = Path('src/zigbind/__init__.pyi')
        if stub_file.exists():
            wf.write(stub_file, 'zigbind/__init__.pyi')
    
    return wheel_path

def _get_platform_tag():
    """Get platform tag for wheel filename."""
    from wheel.bdist_wheel import get_platform
    return get_platform(None).replace('-', '_').replace('.', '_')
```

### 0.4: Hello World Extension

Create `examples/hello_world/src/hello.zig`:

```zig
const std = @import("std");
const zb = @import("zigbind");

export fn PyInit_hello() callconv(.C) ?*zb.PyObject {
    const module = zb.createModule(.{
        .name = "hello",
        .doc = "Hello world module",
        .size = -1,
    }) catch return null;
    
    _ = zb.addFunction(module, .{
        .name = "greet",
        .impl = greet,
        .doc = "Return a greeting",
    }) catch return null;
    
    return module;
}

fn greet(args: *zb.PyObject) callconv(.C) ?*zb.PyObject {
    _ = args;
    return zb.stringFromUtf8("Hello from Zig!") catch null;
}
```

Create `examples/hello_world/build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Add zigbind dependency
    const zigbind = b.dependency("zigbind", .{
        .target = target,
        .optimize = optimize,
    });
    
    // Create extension module
    const hello = b.addSharedLibrary(.{
        .name = "hello",
        .root_source_file = .{ .path = "src/hello.zig" },
        .target = target,
        .optimize = optimize,
    });
    
    // Configure for Python extension
    hello.linkLibC();
    hello.linkSystemLibrary("python3");
    hello.addModule("zigbind", zigbind.module("zigbind"));
    
    // Add Python Limited API define
    hello.defineCMacro("Py_LIMITED_API", "0x030C0000");
    
    b.installArtifact(hello);
}
```

### 0.5: Verification

**Success Criteria:**
1. `pip install .` successfully builds and installs zigbind
2. `python -c "import hello; print(hello.greet())"` outputs "Hello from Zig!"
3. Extension file has correct suffix (`.abi3.so` or `.abi3.pyd`)
4. Works on Python 3.12 and 3.13 without recompilation

**Testing:**
```bash
# Create test environment
python3.12 -m venv venv-312
source venv-312/bin/activate
pip install .
python -c "import hello; print(hello.greet())"

# Test with Python 3.13 (same wheel)
python3.13 -m venv venv-313
source venv-313/bin/activate
pip install dist/*.whl  # Use pre-built wheel
python -c "import hello; print(hello.greet())"
```

---

## Phase 1: Core Architecture (Weeks 2-3)

### Objective
Implement the core C layer that interfaces with Python's Limited API and the Zig API layer that provides ergonomic bindings.

### 1.1: Core C Layer (`src/core/`)

**File: `common.h`**
```c
#ifndef ZIGBIND_COMMON_H
#define ZIGBIND_COMMON_H

#define Py_LIMITED_API 0x030C0000
#include <Python.h>
#include <stdbool.h>

// Forward declarations
typedef struct ZigbindModule ZigbindModule;
typedef struct ZigbindType ZigbindType;
typedef struct ZigbindFunction ZigbindFunction;

// Error codes that map to Python exceptions
typedef enum {
    ZB_OK = 0,
    ZB_ERROR_MEMORY,
    ZB_ERROR_TYPE,
    ZB_ERROR_VALUE,
    ZB_ERROR_RUNTIME,
} ZigbindError;

// Function signature for Zig callbacks
typedef PyObject* (*ZigCallable)(PyObject* self, PyObject* args, PyObject* kwargs);

#endif
```

**File: `module.c`**
```c
#include "common.h"
#include <stdlib.h>

typedef struct {
    PyModuleDef def;
    PyMethodDef* methods;
    size_t method_count;
    size_t method_capacity;
} ZigbindModule;

PyObject* zigbind_create_module(
    const char* name,
    const char* doc,
    Py_ssize_t module_state_size
) {
    ZigbindModule* zm = calloc(1, sizeof(ZigbindModule));
    if (!zm) {
        PyErr_NoMemory();
        return NULL;
    }
    
    zm->method_capacity = 16;
    zm->methods = calloc(zm->method_capacity + 1, sizeof(PyMethodDef));
    if (!zm->methods) {
        free(zm);
        PyErr_NoMemory();
        return NULL;
    }
    
    // Configure PyModuleDef
    PyModuleDef* def = &zm->def;
    memset(def, 0, sizeof(PyModuleDef));
    def->m_base = PyModuleDef_HEAD_INIT;
    def->m_name = name;
    def->m_doc = doc;
    def->m_size = module_state_size;
    def->m_methods = zm->methods;
    
    return PyModule_Create(def);
}

int zigbind_add_function(
    PyObject* module,
    const char* name,
    ZigCallable func,
    const char* doc,
    int flags
) {
    ZigbindModule* zm = PyModule_GetState(module);
    if (!zm) return -1;
    
    if (zm->method_count >= zm->method_capacity) {
        // Resize methods array
        size_t new_capacity = zm->method_capacity * 2;
        PyMethodDef* new_methods = realloc(
            zm->methods, 
            (new_capacity + 1) * sizeof(PyMethodDef)
        );
        if (!new_methods) {
            PyErr_NoMemory();
            return -1;
        }
        zm->methods = new_methods;
        zm->method_capacity = new_capacity;
    }
    
    PyMethodDef* method = &zm->methods[zm->method_count];
    method->ml_name = name;
    method->ml_meth = (PyCFunction)func;
    method->ml_flags = flags;
    method->ml_doc = doc;
    
    zm->method_count++;
    
    // Null-terminate the array
    memset(&zm->methods[zm->method_count], 0, sizeof(PyMethodDef));
    
    return PyModule_AddObject(
        module, 
        name, 
        PyCFunction_New(method, module)
    );
}
```

**File: `type.c`**
```c
#include "common.h"

PyTypeObject* zigbind_create_type(
    const char* name,
    const char* doc,
    size_t basicsize,
    PyType_Spec* spec
) {
    // Use PyType_FromSpec for Limited API compatibility
    PyType_Slot* slots = spec->slots;
    
    spec->name = name;
    spec->basicsize = basicsize;
    spec->itemsize = 0;
    spec->flags = Py_TPFLAGS_DEFAULT | Py_TPFLAGS_HEAPTYPE;
    
    PyObject* type = PyType_FromSpec(spec);
    if (!type) return NULL;
    
    return (PyTypeObject*)type;
}
```

### 1.2: Zig API Layer

**File: `src/zigbind.zig`**
```zig
const std = @import("std");

// Opaque types for Python C API
pub const PyObject = opaque {};
pub const PyTypeObject = opaque {};

// C functions from our core library
extern "c" fn zigbind_create_module(
    name: [*:0]const u8,
    doc: [*:0]const u8,
    module_state_size: isize,
) ?*PyObject;

extern "c" fn zigbind_add_function(
    module: *PyObject,
    name: [*:0]const u8,
    func: *const fn(*PyObject, *PyObject, *PyObject) callconv(.C) ?*PyObject,
    doc: [*:0]const u8,
    flags: c_int,
) c_int;

// Python C API functions (Limited API)
extern "c" fn PyErr_SetString(exc: *PyObject, message: [*:0]const u8) void;
extern "c" fn PyUnicode_FromStringAndSize(str: [*]const u8, size: isize) ?*PyObject;
extern "c" fn Py_INCREF(obj: *PyObject) void;
extern "c" fn Py_DECREF(obj: *PyObject) void;

// Module creation helpers
pub const ModuleConfig = struct {
    name: [:0]const u8,
    doc: [:0]const u8 = "",
    size: isize = -1,
};

pub fn createModule(config: ModuleConfig) !*PyObject {
    return zigbind_create_module(
        config.name.ptr,
        config.doc.ptr,
        config.size,
    ) orelse error.ModuleCreationFailed;
}

pub const FunctionConfig = struct {
    name: [:0]const u8,
    impl: *const fn(*PyObject, *PyObject, *PyObject) callconv(.C) ?*PyObject,
    doc: [:0]const u8 = "",
    flags: c_int = 0x0003, // METH_VARARGS | METH_KEYWORDS
};

pub fn addFunction(module: *PyObject, config: FunctionConfig) !void {
    const result = zigbind_add_function(
        module,
        config.name.ptr,
        config.impl,
        config.doc.ptr,
        config.flags,
    );
    if (result != 0) return error.FunctionAddFailed;
}

// Utility functions
pub fn stringFromUtf8(str: []const u8) !*PyObject {
    return PyUnicode_FromStringAndSize(
        str.ptr,
        @intCast(str.len),
    ) orelse error.StringCreationFailed;
}

pub fn incref(obj: *PyObject) void {
    Py_INCREF(obj);
}

pub fn decref(obj: *PyObject) void {
    Py_DECREF(obj);
}
```

### 1.3: Build System Integration

**File: `src/build_support.zig`**
```zig
const std = @import("std");

/// Helper to configure a shared library as a Python extension module
pub fn configurePythonExtension(
    lib: *std.Build.Step.Compile,
    options: struct {
        python_version: []const u8 = "3.12",
        stable_abi: bool = true,
    },
) void {
    lib.linkLibC();
    lib.linkSystemLibrary("python3");
    
    if (options.stable_abi) {
        // Define Py_LIMITED_API for stable ABI
        lib.defineCMacro("Py_LIMITED_API", "0x030C0000");
    }
    
    // Platform-specific configuration
    switch (lib.target.result.os.tag) {
        .windows => {
            // Windows: link against python3.lib
            lib.addLibraryPath(.{ .cwd_relative = "C:/Python312/libs" });
        },
        .macos => {
            // macOS: use framework
            lib.linkFramework("Python");
        },
        .linux => {
            // Linux: use pkg-config
            lib.linkSystemLibrary("python3-embed");
        },
        else => {},
    }
}

/// Get the correct extension suffix for the platform
pub fn getExtensionSuffix(target: std.Target, stable_abi: bool) []const u8 {
    if (stable_abi) {
        return switch (target.os.tag) {
            .windows => ".abi3.pyd",
            else => ".abi3.so",
        };
    } else {
        // Version-specific suffix
        return switch (target.os.tag) {
            .windows => ".pyd",
            .macos => ".so",
            else => ".so",
        };
    }
}
```

### 1.4: Testing

Create `tests/test_core.py`:

```python
import pytest
import sys

def test_module_creation():
    """Test that module can be created and imported."""
    import hello
    assert hello.__name__ == "hello"

def test_function_call():
    """Test basic function calling."""
    import hello
    result = hello.greet()
    assert result == "Hello from Zig!"
    assert isinstance(result, str)

def test_stable_abi():
    """Verify extension uses stable ABI."""
    import hello
    import importlib
    import inspect
    
    module_file = inspect.getfile(hello)
    if sys.platform == 'win32':
        assert module_file.endswith('.abi3.pyd')
    else:
        assert module_file.endswith('.abi3.so')
```

---

## Phase 2: Build Backend (Weeks 4-5)

### Objective
Implement a robust PEP 517 build backend similar to scikit-build-core that orchestrates the Zig build system, handling configuration, cross-compilation, and wheel generation.

### 2.1: Enhanced Build Backend

**File: `_backend/backend.py`**

```python
"""
Zigbind Build Backend
A PEP 517 build backend that wraps 'zig build'
"""
import os
import sys
import subprocess
import tempfile
import shutil
import sysconfig
from pathlib import Path
from typing import Optional, Dict, List, Any

class ZigbindBackend:
    """Main build backend implementation."""
    
    def __init__(self, source_dir: Path):
        self.source_dir = source_dir
        self.config: Dict[str, Any] = {}
        self._load_config()
    
    def _load_config(self):
        """Load configuration from pyproject.toml."""
        try:
            import tomllib
        except ImportError:
            import tomli as tomllib
        
        pyproject_path = self.source_dir / 'pyproject.toml'
        with open(pyproject_path, 'rb') as f:
            data = tomllib.load(f)
        
        self.config = data.get('tool', {}).get('zigbind', {})
        self.project_config = data.get('project', {})
    
    def get_zig_version(self) -> str:
        """Get installed Zig version."""
        result = subprocess.run(
            ['zig', 'version'],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()
    
    def build_extension(
        self,
        build_dir: Path,
        config_settings: Optional[Dict[str, str]] = None,
    ) -> Path:
        """Run zig build to create extension module."""
        
        # Parse configuration
        config_settings = config_settings or {}
        optimize = config_settings.get('optimize', 'ReleaseFast')
        zig_args = config_settings.get('zig-args', '').split()
        
        # Ensure build directory exists
        build_dir.mkdir(parents=True, exist_ok=True)
        
        # Build command
        cmd = [
            'zig', 'build',
            f'--prefix={build_dir}',
            f'-Doptimize={optimize}',
        ]
        
        # Add stable ABI flag if configured
        if self.config.get('stable-abi', True):
            cmd.append('-Dstable-abi=true')
        
        cmd.extend(zig_args)
        
        # Run build
        print(f"Running: {' '.join(cmd)}")
        subprocess.run(cmd, cwd=self.source_dir, check=True)
        
        return build_dir
    
    def create_wheel(
        self,
        build_dir: Path,
        wheel_dir: Path,
        metadata: Dict[str, str],
    ) -> str:
        """Create wheel from build artifacts."""
        from wheel.wheelfile import WheelFile
        
        # Determine wheel filename
        name = metadata['name'].replace('-', '_')
        version = metadata['version']
        python_tag = self._get_python_tag()
        abi_tag = self._get_abi_tag()
        platform_tag = self._get_platform_tag()
        
        wheel_name = f"{name}-{version}-{python_tag}-{abi_tag}-{platform_tag}.whl"
        wheel_path = wheel_dir / wheel_name
        
        with WheelFile(wheel_path, 'w') as wf:
            # Add built extension modules
            lib_dir = build_dir / 'lib'
            if lib_dir.exists():
                for ext_file in lib_dir.rglob('*'):
                    if ext_file.suffix in {'.so', '.pyd', '.abi3.so', '.abi3.pyd'}:
                        arcname = f"{name}/{ext_file.name}"
                        wf.write(str(ext_file), arcname)
            
            # Add Python source files if any
            python_dir = self.source_dir / 'src' / name
            if python_dir.exists():
                for py_file in python_dir.rglob('*.py'):
                    rel_path = py_file.relative_to(python_dir.parent)
                    wf.write(str(py_file), str(rel_path))
        
        return wheel_name
    
    def _get_python_tag(self) -> str:
        """Get Python version tag (e.g., cp312)."""
        if self.config.get('stable-abi', True):
            # Stable ABI works across versions
            return f"cp{sys.version_info.major}{sys.version_info.minor}"
        else:
            return f"cp{sys.version_info.major}{sys.version_info.minor}"
    
    def _get_abi_tag(self) -> str:
        """Get ABI tag."""
        if self.config.get('stable-abi', True):
            return 'abi3'
        else:
            return sysconfig.get_config_var('SOABI').split('-')[1]
    
    def _get_platform_tag(self) -> str:
        """Get platform tag."""
        from wheel.bdist_wheel import get_platform
        return get_platform(None).replace('-', '_').replace('.', '_')

# PEP 517 hooks
def build_wheel(
    wheel_directory: str,
    config_settings: Optional[Dict[str, str]] = None,
    metadata_directory: Optional[str] = None,
) -> str:
    """Build a wheel."""
    source_dir = Path.cwd()
    backend = ZigbindBackend(source_dir)
    
    # Build extension
    build_dir = source_dir / 'build' / 'temp'
    backend.build_extension(build_dir, config_settings)
    
    # Create wheel
    wheel_dir = Path(wheel_directory)
    wheel_dir.mkdir(parents=True, exist_ok=True)
    
    metadata = {
        'name': backend.project_config['name'],
        'version': backend.project_config['version'],
    }
    
    return backend.create_wheel(build_dir, wheel_dir, metadata)

def build_sdist(
    sdist_directory: str,
    config_settings: Optional[Dict[str, str]] = None,
) -> str:
    """Build a source distribution."""
    import tarfile
    
    source_dir = Path.cwd()
    backend = ZigbindBackend(source_dir)
    
    name = backend.project_config['name']
    version = backend.project_config['version']
    
    sdist_name = f"{name}-{version}.tar.gz"
    sdist_path = Path(sdist_directory) / sdist_name
    
    with tarfile.open(sdist_path, 'w:gz') as tar:
        # Add all source files
        for pattern in ['src', 'build.zig', 'build.zig.zon', 
                       'pyproject.toml', 'README.md', 'LICENSE']:
            for path in source_dir.glob(pattern):
                arcname = f"{name}-{version}/{path.relative_to(source_dir)}"
                tar.add(str(path), arcname=arcname)
    
    return sdist_name

def get_requires_for_build_wheel(config_settings: Optional[Dict] = None) -> List[str]:
    """Return build requirements."""
    return ["wheel"]

def get_requires_for_build_sdist(config_settings: Optional[Dict] = None) -> List[str]:
    """Return sdist build requirements."""
    return []
```

### 2.2: Configuration Schema

Add to `pyproject.toml`:

```toml
[tool.zigbind]
# Enable stable ABI (default: true)
stable-abi = true

# Zig build optimization (default: "ReleaseFast")
# Options: "Debug", "ReleaseSafe", "ReleaseFast", "ReleaseSmall"
optimize = "ReleaseFast"

# Additional Zig build arguments
zig-args = []

# Python version constraint for stable ABI
minimum-python = "3.12"
```

### 2.3: Cross-Compilation Support

**File: `_backend/targets.py`**

```python
"""Target platform configuration for cross-compilation."""

TARGET_CONFIGS = {
    'linux-x86_64': {
        'zig_target': 'x86_64-linux-gnu',
        'wheel_platform': 'manylinux_2_17_x86_64.manylinux2014_x86_64',
    },
    'linux-aarch64': {
        'zig_target': 'aarch64-linux-gnu',
        'wheel_platform': 'manylinux_2_17_aarch64.manylinux2014_aarch64',
    },
    'macos-x86_64': {
        'zig_target': 'x86_64-macos',
        'wheel_platform': 'macosx_10_9_x86_64',
    },
    'macos-arm64': {
        'zig_target': 'aarch64-macos',
        'wheel_platform': 'macosx_11_0_arm64',
    },
    'windows-x86_64': {
        'zig_target': 'x86_64-windows',
        'wheel_platform': 'win_amd64',
    },
}

def get_target_config(target: str):
    """Get cross-compilation configuration."""
    return TARGET_CONFIGS.get(target)
```

---

## Phase 3: Basic Bindings (Weeks 6-8)

### Objective
Implement core binding functionality: functions, classes, methods, and basic type conversion.

### 3.1: Function Bindings

**File: `src/function.zig`**

```zig
const std = @import("std");
const py = @import("python_api.zig");

/// Function metadata
pub const FunctionMeta = struct {
    name: [:0]const u8,
    doc: [:0]const u8 = "",
    /// Zig function to wrap
    func: anytype,
    /// Argument specification
    args: []const ArgSpec = &.{},
};

pub const ArgSpec = struct {
    name: [:0]const u8,
    type: type,
    default: ?*const anyopaque = null,
    allow_none: bool = false,
};

/// Register a Zig function as a Python callable
pub fn defineFunction(
    module: *py.PyObject,
    comptime meta: FunctionMeta,
) !void {
    const wrapper = struct {
        fn call(
            self: *py.PyObject,
            args: *py.PyObject,
            kwargs: *py.PyObject,
        ) callconv(.C) ?*py.PyObject {
            // Parse arguments
            const zig_args = parseArgs(args, kwargs, meta.args) catch {
                return null;
            };
            
            // Call Zig function
            const result = @call(.auto, meta.func, zig_args) catch |err| {
                py.setException(err);
                return null;
            };
            
            // Convert result to Python
            return py.toPython(result) catch null;
        }
    };
    
    try py.addFunction(module, .{
        .name = meta.name,
        .impl = wrapper.call,
        .doc = meta.doc,
    });
}

/// Parse Python arguments into Zig types
fn parseArgs(
    args: *py.PyObject,
    kwargs: *py.PyObject,
    spec: []const ArgSpec,
) !std.meta.Tuple(&[_]type{ArgSpec.type}) {
    // Implementation: use PyArg_ParseTupleAndKeywords equivalent
    _ = args;
    _ = kwargs;
    _ = spec;
    @panic("TODO: implement argument parsing");
}
```

### 3.2: Class Bindings

**File: `src/class.zig`**

```zig
const std = @import("std");
const py = @import("python_api.zig");

pub const ClassMeta = struct {
    name: [:0]const u8,
    doc: [:0]const u8 = "",
    type: type,
};

/// Define a Python class from a Zig struct
pub fn defineClass(
    module: *py.PyObject,
    comptime meta: ClassMeta,
) !*py.PyTypeObject {
    const T = meta.type;
    
    // Generate PyType_Spec
    var slots = std.ArrayList(py.PyType_Slot).init(std.heap.page_allocator);
    defer slots.deinit();
    
    // Add tp_dealloc
    try slots.append(.{
        .slot = py.Py_tp_dealloc,
        .pfunc = @ptrCast(&deallocWrapper(T)),
    });
    
    // Add tp_new
    try slots.append(.{
        .slot = py.Py_tp_new,
        .pfunc = @ptrCast(&newWrapper(T)),
    });
    
    // Null terminator
    try slots.append(.{ .slot = 0, .pfunc = null });
    
    // Create type spec
    const spec = py.PyType_Spec{
        .name = meta.name.ptr,
        .basicsize = @sizeOf(InstanceWrapper(T)),
        .itemsize = 0,
        .flags = py.Py_TPFLAGS_DEFAULT,
        .slots = slots.items.ptr,
    };
    
    // Create type
    const type_obj = try py.createTypeFromSpec(&spec);
    
    // Add to module
    try py.addType(module, meta.name, type_obj);
    
    return type_obj;
}

/// Wrapper that stores Zig instance alongside PyObject
fn InstanceWrapper(comptime T: type) type {
    return struct {
        // PyObject header (managed by Python)
        py_object: py.PyObject,
        // Zig instance data
        instance: T,
    };
}

fn newWrapper(comptime T: type) fn(*py.PyTypeObject, *py.PyObject, *py.PyObject) callconv(.C) ?*py.PyObject {
    return struct {
        fn call(
            type_obj: *py.PyTypeObject,
            args: *py.PyObject,
            kwargs: *py.PyObject,
        ) callconv(.C) ?*py.PyObject {
            _ = args;
            _ = kwargs;
            
            // Allocate instance
            const self = py.allocateInstance(type_obj) catch return null;
            const wrapper = @ptrCast(*InstanceWrapper(T), @alignCast(self));
            
            // Initialize Zig instance
            wrapper.instance = T{};
            
            return self;
        }
    }.call;
}

fn deallocWrapper(comptime T: type) fn(*py.PyObject) callconv(.C) void {
    return struct {
        fn call(self: *py.PyObject) callconv(.C) void {
            const wrapper = @ptrCast(*InstanceWrapper(T), @alignCast(self));
            
            // Deinit Zig instance if needed
            if (@hasDecl(T, "deinit")) {
                wrapper.instance.deinit();
            }
            
            // Free Python object
            py.freeInstance(self);
        }
    }.call;
}
```

### 3.3: Method Bindings

**File: `src/method.zig`**

```zig
/// Add method to class
pub fn defineMethod(
    type_obj: *py.PyTypeObject,
    comptime meta: struct {
        name: [:0]const u8,
        func: anytype,
        doc: [:0]const u8 = "",
    },
) !void {
    const wrapper = struct {
        fn call(
            self: *py.PyObject,
            args: *py.PyObject,
            kwargs: *py.PyObject,
        ) callconv(.C) ?*py.PyObject {
            // Extract Zig instance
            const T = @TypeOf(meta.func).Params[0].type;
            const instance = py.getInstance(T, self) catch return null;
            
            // Parse arguments
            const zig_args = parseMethodArgs(args, kwargs) catch return null;
            
            // Call method
            const result = @call(.auto, meta.func, .{instance} ++ zig_args) catch |err| {
                py.setException(err);
                return null;
            };
            
            // Convert result
            return py.toPython(result) catch null;
        }
    };
    
    try py.addMethod(type_obj, .{
        .name = meta.name,
        .impl = wrapper.call,
        .doc = meta.doc,
    });
}
```

### 3.4: Example Usage

```zig
const zb = @import("zigbind");

const Vec2 = struct {
    x: f64,
    y: f64,
    
    pub fn init(x: f64, y: f64) Vec2 {
        return .{ .x = x, .y = y };
    }
    
    pub fn length(self: *const Vec2) f64 {
        return @sqrt(self.x * self.x + self.y * self.y);
    }
    
    pub fn add(self: *const Vec2, other: *const Vec2) Vec2 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }
};

export fn PyInit_vectors() callconv(.C) ?*zb.PyObject {
    const module = zb.createModule(.{
        .name = "vectors",
        .doc = "2D vector operations",
    }) catch return null;
    
    // Register Vec2 class
    const Vec2Type = zb.defineClass(module, .{
        .name = "Vec2",
        .doc = "2D vector",
        .type = Vec2,
    }) catch return null;
    
    // Add constructor
    zb.defineMethod(Vec2Type, .{
        .name = "__init__",
        .func = Vec2.init,
    }) catch return null;
    
    // Add methods
    zb.defineMethod(Vec2Type, .{
        .name = "length",
        .func = Vec2.length,
        .doc = "Calculate vector length",
    }) catch return null;
    
    zb.defineMethod(Vec2Type, .{
        .name = "add",
        .func = Vec2.add,
        .doc = "Add two vectors",
    }) catch return null;
    
    return module;
}
```

---

## Phase 4: Type System (Weeks 9-11)

### Objective
Implement type casters for automatic conversion between Zig and Python types, following nanobind's model.

### 4.1: Type Caster Framework

**File: `src/type_caster.zig`**

```zig
pub fn TypeCaster(comptime T: type) type {
    return struct {
        /// Convert Python object to Zig value
        pub fn fromPython(obj: *py.PyObject) !T {
            // Dispatch to specialized converters
            return switch (@typeInfo(T)) {
                .Int => fromPythonInt(T, obj),
                .Float => fromPythonFloat(T, obj),
                .Bool => fromPythonBool(obj),
                .Pointer => fromPythonPointer(T, obj),
                .Optional => fromPythonOptional(T, obj),
                .Struct => fromPythonStruct(T, obj),
                .Enum => fromPythonEnum(T, obj),
                .Union => fromPythonUnion(T, obj),
                else => @compileError("Unsupported type: " ++ @typeName(T)),
            };
        }
        
        /// Convert Zig value to Python object
        pub fn toPython(value: T) !*py.PyObject {
            return switch (@typeInfo(T)) {
                .Int => toPythonInt(value),
                .Float => toPythonFloat(value),
                .Bool => toPythonBool(value),
                .Pointer => toPythonPointer(value),
                .Optional => toPythonOptional(value),
                .Struct => toPythonStruct(value),
                .Enum => toPythonEnum(value),
                .Union => toPythonUnion(value),
                else => @compileError("Unsupported type: " ++ @typeName(T)),
            };
        }
    };
}
```

### 4.2: Built-in Type Converters

**File: `src/std/primitives.zig`**

```zig
/// Integer conversion
pub fn fromPythonInt(comptime T: type, obj: *py.PyObject) !T {
    const long_val = py.PyLong_AsLongLong(obj);
    if (py.PyErr_Occurred() != null) {
        return error.TypeError;
    }
    return std.math.cast(T, long_val) orelse error.OverflowError;
}

pub fn toPythonInt(value: anytype) !*py.PyObject {
    return py.PyLong_FromLongLong(value) orelse error.MemoryError;
}

/// Float conversion
pub fn fromPythonFloat(comptime T: type, obj: *py.PyObject) !T {
    const float_val = py.PyFloat_AsDouble(obj);
    if (py.PyErr_Occurred() != null) {
        return error.TypeError;
    }
    return @floatCast(float_val);
}

pub fn toPythonFloat(value: anytype) !*py.PyObject {
    return py.PyFloat_FromDouble(@floatCast(value)) orelse error.MemoryError;
}

/// Bool conversion  
pub fn fromPythonBool(obj: *py.PyObject) !bool {
    const is_true = py.PyObject_IsTrue(obj);
    if (is_true < 0) return error.TypeError;
    return is_true == 1;
}

pub fn toPythonBool(value: bool) !*py.PyObject {
    return if (value) py.Py_True() else py.Py_False();
}
```

**File: `src/std/string.zig`**

```zig
/// String conversion (UTF-8)
pub fn fromPythonString(obj: *py.PyObject, allocator: std.mem.Allocator) ![]u8 {
    var size: isize = undefined;
    const ptr = py.PyUnicode_AsUTF8AndSize(obj, &size);
    if (ptr == null) return error.TypeError;
    
    const bytes = ptr[0..@intCast(size)];
    return try allocator.dupe(u8, bytes);
}

pub fn toPythonString(str: []const u8) !*py.PyObject {
    return py.PyUnicode_FromStringAndSize(
        str.ptr,
        @intCast(str.len),
    ) orelse error.MemoryError;
}

/// String slice (no allocation, view into Python string)
pub fn fromPythonStringSlice(obj: *py.PyObject) ![]const u8 {
    var size: isize = undefined;
    const ptr = py.PyUnicode_AsUTF8AndSize(obj, &size);
    if (ptr == null) return error.TypeError;
    
    return ptr[0..@intCast(size)];
}
```

**File: `src/std/list.zig`**

```zig
/// List conversion
pub fn fromPythonList(
    comptime T: type,
    obj: *py.PyObject,
    allocator: std.mem.Allocator,
) ![]T {
    if (py.PyList_Check(obj) == 0) {
        return error.TypeError;
    }
    
    const size = py.PyList_Size(obj);
    var list = try allocator.alloc(T, @intCast(size));
    
    for (0..@intCast(size)) |i| {
        const item = py.PyList_GetItem(obj, @intCast(i));
        list[i] = try TypeCaster(T).fromPython(item);
    }
    
    return list;
}

pub fn toPythonList(comptime T: type, items: []const T) !*py.PyObject {
    const list = py.PyList_New(@intCast(items.len)) orelse return error.MemoryError;
    
    for (items, 0..) |item, i| {
        const py_item = try TypeCaster(T).toPython(item);
        _ = py.PyList_SetItem(list, @intCast(i), py_item);
    }
    
    return list;
}
```

### 4.3: Optional and Error Handling

**File: `src/std/optional.zig`**

```zig
/// Optional type handling (Zig optional <-> Python None)
pub fn fromPythonOptional(comptime T: type, obj: *py.PyObject) !?T {
    if (py.isNone(obj)) {
        return null;
    }
    
    const Inner = @typeInfo(T).Optional.child;
    return try TypeCaster(Inner).fromPython(obj);
}

pub fn toPythonOptional(comptime T: type, value: ?T) !*py.PyObject {
    if (value) |v| {
        return try TypeCaster(T).toPython(v);
    } else {
        py.incref(py.Py_None());
        return py.Py_None();
    }
}
```

**File: `src/std/errors.zig`**

```zig
/// Error set mapping
pub const ErrorMap = struct {
    zig_error: anyerror,
    py_exception: *py.PyObject,
    message: [:0]const u8,
};

pub fn mapErrorToPython(err: anyerror) *py.PyObject {
    return switch (err) {
        error.OutOfMemory => py.PyExc_MemoryError(),
        error.InvalidUtf8 => py.PyExc_UnicodeError(),
        error.Overflow => py.PyExc_OverflowError(),
        error.TypeError => py.PyExc_TypeError(),
        error.ValueError => py.PyExc_ValueError(),
        error.KeyError => py.PyExc_KeyError(),
        error.IndexError => py.PyExc_IndexError(),
        else => py.PyExc_RuntimeError(),
    };
}

pub fn setException(err: anyerror) void {
    const exc = mapErrorToPython(err);
    const msg = @errorName(err);
    py.PyErr_SetString(exc, msg.ptr);
}
```

### 4.4: Example: Complex Type Conversion

```zig
const Point = struct {
    x: f64,
    y: f64,
};

const Shape = union(enum) {
    circle: struct { center: Point, radius: f64 },
    rectangle: struct { top_left: Point, bottom_right: Point },
};

// Automatic conversion
export fn PyInit_shapes() callconv(.C) ?*zb.PyObject {
    const module = zb.createModule(.{
        .name = "shapes",
    }) catch return null;
    
    // Function that takes Shape union
    zb.defineFunction(module, .{
        .name = "area",
        .func = calculateArea,
    }) catch return null;
    
    return module;
}

fn calculateArea(shape: Shape) f64 {
    return switch (shape) {
        .circle => |c| std.math.pi * c.radius * c.radius,
        .rectangle => |r| (r.bottom_right.x - r.top_left.x) * 
                          (r.bottom_right.y - r.top_left.y),
    };
}
```

---

## Phase 5: Advanced Features (Weeks 12-15)

### Objective
Implement operators, properties, enums, error handling, and virtual functions.

### 5.1: Operator Overloading

**File: `src/operators.zig`**

```zig
pub const Operator = enum {
    add,        // __add__
    sub,        // __sub__
    mul,        // __mul__
    truediv,    // __truediv__
    floordiv,   // __floordiv__
    mod,        // __mod__
    pow,        // __pow__
    eq,         // __eq__
    ne,         // __ne__
    lt,         // __lt__
    le,         // __le__
    gt,         // __gt__
    ge,         // __ge__
    neg,        // __neg__
    pos,        // __pos__
    abs,        // __abs__
    invert,     // __invert__
    
    pub fn slotId(self: Operator) c_int {
        return switch (self) {
            .add => py.Py_nb_add,
            .sub => py.Py_nb_subtract,
            .mul => py.Py_nb_multiply,
            .truediv => py.Py_nb_true_divide,
            // ... etc
        };
    }
    
    pub fn methodName(self: Operator) [:0]const u8 {
        return switch (self) {
            .add => "__add__",
            .sub => "__sub__",
            // ... etc
        };
    }
};

pub fn defineOperator(
    type_obj: *py.PyTypeObject,
    comptime op: Operator,
    comptime func: anytype,
) !void {
    // Create wrapper
    const wrapper = makeOperatorWrapper(op, func);
    
    // Add as slot
    try py.addSlot(type_obj, op.slotId(), wrapper);
}
```

### 5.2: Properties (Getters/Setters)

**File: `src/property.zig`**

```zig
pub const PropertyMeta = struct {
    name: [:0]const u8,
    doc: [:0]const u8 = "",
    getter: ?anytype = null,
    setter: ?anytype = null,
    readonly: bool = false,
};

pub fn defineProperty(
    type_obj: *py.PyTypeObject,
    comptime meta: PropertyMeta,
) !void {
    const getter_wrapper = if (meta.getter) |g|
        makeGetterWrapper(g)
    else
        null;
    
    const setter_wrapper = if (meta.setter) |s|
        makeSetterWrapper(s)
    else
        null;
    
    // Create property descriptor
    const prop = py.PyDescr_NewGetSet(
        type_obj,
        &py.PyGetSetDef{
            .name = meta.name.ptr,
            .get = getter_wrapper,
            .set = if (meta.readonly) null else setter_wrapper,
            .doc = meta.doc.ptr,
            .closure = null,
        },
    ) orelse return error.PropertyCreationFailed;
    
    try py.addProperty(type_obj, meta.name, prop);
}
```

### 5.3: Enum Binding

**File: `src/enum.zig`**

```zig
pub fn defineEnum(
    module: *py.PyObject,
    comptime meta: struct {
        name: [:0]const u8,
        type: type,
        doc: [:0]const u8 = "",
    },
) !*py.PyTypeObject {
    const T = meta.type;
    const info = @typeInfo(T).Enum;
    
    // Create enum type
    const enum_type = try py.createEnumType(meta.name, meta.doc);
    
    // Add enum values
    inline for (info.fields) |field| {
        const value = @field(T, field.name);
        const int_value = @intFromEnum(value);
        
        try py.addEnumValue(
            enum_type,
            field.name,
            int_value,
        );
    }
    
    // Add to module
    try py.addType(module, meta.name, enum_type);
    
    return enum_type;
}

// Example usage
const Color = enum {
    red,
    green,
    blue,
};

export fn PyInit_colors() callconv(.C) ?*zb.PyObject {
    const module = zb.createModule(.{ .name = "colors" }) catch return null;
    
    _ = zb.defineEnum(module, .{
        .name = "Color",
        .type = Color,
        .doc = "RGB colors",
    }) catch return null;
    
    return module;
}
```

### 5.4: Virtual Functions / Trampolines

**File: `src/trampoline.zig`**

```zig
/// Base class with virtual methods
pub const VirtualClass = struct {
    /// Mark methods as virtual
    pub fn virtualMethod(
        comptime meta: struct {
            name: [:0]const u8,
            func: anytype,
        },
    ) void {
        // Compile-time marker for virtual methods
        _ = meta;
    }
};

/// Create trampoline for Python subclass
pub fn Trampoline(comptime Base: type) type {
    return struct {
        base: Base,
        py_obj: *py.PyObject,
        
        const Self = @This();
        
        pub fn create(py_obj: *py.PyObject) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .base = Base{},
                .py_obj = py_obj,
            };
            py.incref(py_obj);
            return self;
        }
        
        pub fn destroy(self: *Self) void {
            py.decref(self.py_obj);
            allocator.destroy(self);
        }
        
        /// Call Python override if exists, otherwise call base
        pub fn callVirtual(
            self: *Self,
            comptime method_name: [:0]const u8,
            args: anytype,
        ) !@TypeOf(@field(Base, method_name)(&self.base, args)) {
            // Check for Python override
            const py_method = py.getAttr(self.py_obj, method_name) catch {
                // No override, call base
                return @call(.auto, @field(Base, method_name), .{&self.base} ++ args);
            };
            defer py.decref(py_method);
            
            // Call Python method
            const py_args = try py.toPythonTuple(args);
            defer py.decref(py_args);
            
            const result = py.callObject(py_method, py_args) catch |err| {
                return err;
            };
            defer py.decref(result);
            
            // Convert result back to Zig
            return try py.fromPython(@TypeOf(@field(Base, method_name)(&self.base, args)), result);
        }
    };
}
```

### 5.5: Keyword Arguments

**File: `src/kwargs.zig`**

```zig
pub const KwargSpec = struct {
    name: [:0]const u8,
    type: type,
    default: ?*const anyopaque = null,
    required: bool = true,
};

pub fn parseKwargs(
    comptime specs: []const KwargSpec,
    args: *py.PyObject,
    kwargs: *py.PyObject,
) !std.meta.Tuple(&specs) {
    // Parse positional args
    const n_args = py.PyTuple_Size(args);
    
    // Parse keyword args
    var result: std.meta.Tuple(&specs) = undefined;
    
    inline for (specs, 0..) |spec, i| {
        if (i < n_args) {
            // Get from positional args
            const arg = py.PyTuple_GetItem(args, i);
            result[i] = try TypeCaster(spec.type).fromPython(arg);
        } else if (kwargs != null) {
            // Try to get from kwargs
            const kwarg = py.PyDict_GetItemString(kwargs, spec.name.ptr);
            if (kwarg != null) {
                result[i] = try TypeCaster(spec.type).fromPython(kwarg);
            } else if (spec.default) |default_ptr| {
                // Use default value
                const default_val = @as(*const spec.type, @ptrCast(@alignCast(default_ptr))).*;
                result[i] = default_val;
            } else if (spec.required) {
                return error.MissingArgument;
            }
        } else if (spec.required) {
            return error.MissingArgument;
        }
    }
    
    return result;
}
```

---

## Phase 6: Stub Generation (Weeks 16-17)

### Objective
Implement automatic `.pyi` stub file generation with `__nb_signature__` property for type checking and IDE support.

### 6.1: Signature Metadata

**File: `src/signature.zig`**

```zig
/// Signature information for stub generation
pub const Signature = struct {
    name: []const u8,
    params: []const Parameter,
    return_type: []const u8,
    doc: []const u8,
    overloads: []const Signature = &.{},
};

pub const Parameter = struct {
    name: []const u8,
    type_name: []const u8,
    default: ?[]const u8 = null,
    kind: enum { positional, keyword_only, var_positional, var_keyword },
};

/// Generate signature from Zig function at compile time
pub fn generateSignature(comptime func: anytype) Signature {
    const func_info = @typeInfo(@TypeOf(func)).Fn;
    
    var params: [func_info.params.len]Parameter = undefined;
    
    inline for (func_info.params, 0..) |param, i| {
        params[i] = .{
            .name = param.name orelse std.fmt.comptimePrint("arg{}", .{i}),
            .type_name = pythonTypeName(param.type),
            .kind = .positional,
        };
    }
    
    return .{
        .name = @typeName(func),
        .params = &params,
        .return_type = pythonTypeName(func_info.return_type),
        .doc = "",
    };
}

/// Map Zig type to Python type annotation
fn pythonTypeName(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .Int => "int",
        .Float => "float",
        .Bool => "bool",
        .Pointer => |ptr| {
            if (ptr.child == u8) return "str";
            return std.fmt.comptimePrint("list[{}]", .{pythonTypeName(ptr.child)});
        },
        .Optional => |opt| std.fmt.comptimePrint("{} | None", .{pythonTypeName(opt.child)}),
        .Struct => @typeName(T),
        .Enum => @typeName(T),
        else => "Any",
    };
}
```

### 6.2: Stub Generator CLI

**File: `tools/stubgen.zig`**

```zig
const std = @import("std");
const py = @import("python_api.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 2) {
        std.debug.print("Usage: zigbind-stubgen <module_name>\n", .{});
        return;
    }
    
    const module_name = args[1];
    
    // Initialize Python
    py.Py_Initialize();
    defer py.Py_Finalize();
    
    // Import module
    const module = py.PyImport_ImportModule(module_name.ptr) orelse {
        std.debug.print("Failed to import module: {s}\n", .{module_name});
        return error.ImportFailed;
    };
    defer py.decref(module);
    
    // Generate stub
    var stub = std.ArrayList(u8).init(allocator);
    defer stub.deinit();
    
    try generateModuleStub(module, &stub);
    
    // Write to file
    const filename = try std.fmt.allocPrint(allocator, "{s}.pyi", .{module_name});
    defer allocator.free(filename);
    
    try std.fs.cwd().writeFile(filename, stub.items);
    
    std.debug.print("Generated: {s}\n", .{filename});
}

fn generateModuleStub(module: *py.PyObject, stub: *std.ArrayList(u8)) !void {
    const writer = stub.writer();
    
    // Header
    try writer.writeAll("# Auto-generated by zigbind-stubgen\n");
    try writer.writeAll("from typing import Any, Optional, overload\n\n");
    
    // Get module dict
    const dict = py.PyModule_GetDict(module);
    
    var pos: isize = 0;
    var key: *py.PyObject = undefined;
    var value: *py.PyObject = undefined;
    
    // Iterate module members
    while (py.PyDict_Next(dict, &pos, &key, &value) != 0) {
        const name = py.PyUnicode_AsUTF8(key);
        
        // Skip private members
        if (name[0] == '_') continue;
        
        // Check member type
        if (py.PyType_Check(value)) {
            try generateClassStub(value, name, writer);
        } else if (py.PyCallable_Check(value)) {
            try generateFunctionStub(value, name, writer);
        }
    }
}

fn generateFunctionStub(
    func: *py.PyObject,
    name: [*:0]const u8,
    writer: anytype,
) !void {
    // Get __nb_signature__ if available
    const sig_attr = py.PyObject_GetAttrString(func, "__nb_signature__");
    
    if (sig_attr != null) {
        defer py.decref(sig_attr);
        
        // Parse signature from __nb_signature__
        const sig_str = py.PyUnicode_AsUTF8(sig_attr);
        try writer.print("{s}\n\n", .{sig_str});
    } else {
        // Fallback: generate basic signature
        const doc = py.PyObject_GetAttrString(func, "__doc__");
        defer if (doc != null) py.decref(doc);
        
        try writer.print("def {s}(*args, **kwargs) -> Any:\n", .{name});
        if (doc != null) {
            const doc_str = py.PyUnicode_AsUTF8(doc);
            try writer.print("    \"\"\"{s}\"\"\"\n", .{doc_str});
        }
        try writer.writeAll("    ...\n\n");
    }
}

fn generateClassStub(
    type_obj: *py.PyObject,
    name: [*:0]const u8,
    writer: anytype,
) !void {
    try writer.print("class {s}:\n", .{name});
    
    // Get class dict
    const dict = py.PyObject_GetAttrString(type_obj, "__dict__");
    defer py.decref(dict);
    
    var pos: isize = 0;
    var key: *py.PyObject = undefined;
    var value: *py.PyObject = undefined;
    
    var has_members = false;
    
    // Iterate class members
    while (py.PyDict_Next(dict, &pos, &key, &value) != 0) {
        const member_name = py.PyUnicode_AsUTF8(key);
        
        // Skip private members
        if (member_name[0] == '_') continue;
        
        if (py.PyCallable_Check(value)) {
            try generateMethodStub(value, member_name, writer);
            has_members = true;
        }
    }
    
    if (!has_members) {
        try writer.writeAll("    pass\n");
    }
    
    try writer.writeAll("\n");
}

fn generateMethodStub(
    method: *py.PyObject,
    name: [*:0]const u8,
    writer: anytype,
) !void {
    // Similar to generateFunctionStub but with 'self' parameter
    const sig_attr = py.PyObject_GetAttrString(method, "__nb_signature__");
    
    if (sig_attr != null) {
        defer py.decref(sig_attr);
        const sig_str = py.PyUnicode_AsUTF8(sig_attr);
        try writer.print("    {s}\n", .{sig_str});
    } else {
        try writer.print("    def {s}(self, *args, **kwargs) -> Any: ...\n", .{name});
    }
}
```

### 6.3: Build Integration

Update `build.zig`:

```zig
pub fn build(b: *std.Build) void {
    // ... existing build configuration
    
    // Add stub generator executable
    const stubgen = b.addExecutable(.{
        .name = "zigbind-stubgen",
        .root_source_file = .{ .path = "tools/stubgen.zig" },
        .target = target,
        .optimize = optimize,
    });
    
    stubgen.linkLibC();
    stubgen.linkSystemLibrary("python3");
    stubgen.defineCMacro("Py_LIMITED_API", "0x030C0000");
    
    b.installArtifact(stubgen);
    
    // Add stub generation step
    const generate_stubs = b.step("stubs", "Generate .pyi stub files");
    const run_stubgen = b.addRunArtifact(stubgen);
    run_stubgen.addArg("my_module");
    generate_stubs.dependOn(&run_stubgen.step);
}
```

---

## Phase 7: Testing & CI (Weeks 18-19)

### Objective
Comprehensive testing infrastructure and CI pipeline.

### 7.1: Test Suite Structure

```
tests/
├── unit/                  # Unit tests
│   ├── test_types.py
│   ├── test_functions.py
│   ├── test_classes.py
│   └── test_operators.py
├── integration/           # Integration tests
│   ├── test_numpy_interop.py
│   ├── test_error_handling.py
│   └── test_memory.py
├── benchmark/            # Performance benchmarks
│   ├── bench_function_call.py
│   ├── bench_type_conversion.py
│   └── bench_object_creation.py
└── conftest.py           # Shared fixtures
```

### 7.2: Test Examples

**File: `tests/unit/test_types.py`**

```python
import pytest
import numpy as np

def test_int_conversion():
    import my_ext
    assert my_ext.echo_int(42) == 42
    assert my_ext.echo_int(-100) == -100

def test_float_conversion():
    import my_ext
    assert abs(my_ext.echo_float(3.14) - 3.14) < 1e-10

def test_string_conversion():
    import my_ext
    assert my_ext.echo_str("hello") == "hello"
    assert my_ext.echo_str("") == ""

def test_list_conversion():
    import my_ext
    result = my_ext.double_list([1, 2, 3])
    assert result == [2, 4, 6]

def test_optional_none():
    import my_ext
    assert my_ext.maybe_none(None) is None
    assert my_ext.maybe_none(42) == 42

def test_error_handling():
    import my_ext
    with pytest.raises(ValueError):
        my_ext.divide(1, 0)
```

### 7.3: CI Configuration

**File: `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        python-version: ['3.12', '3.13']
    
    runs-on: ${{ matrix.os }}
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
      
      - name: Set up Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.0
      
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install pytest pytest-cov wheel
      
      - name: Build extension
        run: pip install -e .
      
      - name: Run tests
        run: pytest tests/ -v --cov=zigbind --cov-report=xml
      
      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          file: ./coverage.xml

  build-wheels:
    name: Build wheels
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-13, macos-14]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.0
      
      - name: Build wheels
        uses: pypa/cibuildwheel@v2.21
        env:
          CIBW_BUILD: cp312-* cp313-*
          CIBW_ARCHS_MACOS: "x86_64 arm64"
          CIBW_ARCHS_LINUX: "x86_64 aarch64"
      
      - uses: actions/upload-artifact@v4
        with:
          name: wheels-${{ matrix.os }}
          path: ./wheelhouse/*.whl
```

### 7.4: Benchmarking

**File: `tests/benchmark/bench_function_call.py`**

```python
import time
import statistics

def benchmark_function_calls():
    import my_ext
    
    # Warmup
    for _ in range(1000):
        my_ext.noop()
    
    # Benchmark
    iterations = 100000
    times = []
    
    for _ in range(10):
        start = time.perf_counter()
        for _ in range(iterations):
            my_ext.noop()
        end = time.perf_counter()
        times.append((end - start) / iterations * 1e9)  # ns per call
    
    print(f"Function call overhead: {statistics.mean(times):.2f} ns")
    print(f"Std dev: {statistics.stdev(times):.2f} ns")

if __name__ == '__main__':
    benchmark_function_calls()
```

---

## Phase 8: Documentation (Week 20)

### Objective
Comprehensive documentation for users and contributors.

### 8.1: Documentation Structure

```
docs/
├── index.md                      # Landing page
├── getting-started/
│   ├── installation.md
│   ├── quickstart.md
│   └── first-extension.md
├── guides/
│   ├── functions.md
│   ├── classes.md
│   ├── type-conversion.md
│   ├── error-handling.md
│   ├── operators.md
│   └── virtual-functions.md
├── api/
│   ├── module.md
│   ├── class.md
│   ├── function.md
│   ├── types.md
│   └── build-system.md
├── advanced/
│   ├── object-ownership.md
│   ├── performance.md
│   ├── stable-abi.md
│   └── internals.md
├── examples/
│   ├── hello-world.md
│   ├── math-library.md
│   ├── game-physics.md
│   └── data-processing.md
└── contributing/
    ├── development-setup.md
    ├── architecture.md
    └── testing.md
```

### 8.2: Example Documentation

**File: `docs/getting-started/first-extension.md`**

````markdown
# Your First Zigbind Extension

This guide walks through creating a simple Python extension module using Zigbind.

## Project Setup

Create a new directory structure:

```
my_extension/
├── pyproject.toml
├── build.zig
└── src/
    ├── my_ext.zig
    └── my_ext/
        └── __init__.py
```

## Configuration

Create `pyproject.toml`:

```toml
[build-system]
requires = ["zigbind>=0.1.0"]
build-backend = "zigbind.build"

[project]
name = "my-extension"
version = "0.1.0"
requires-python = ">=3.12"

[tool.zigbind]
stable-abi = true
```

## Implementation

Create `src/my_ext.zig`:

```zig
const zb = @import("zigbind");

export fn PyInit_my_ext() callconv(.C) ?*zb.PyObject {
    const module = zb.createModule(.{
        .name = "my_ext",
        .doc = "My first extension",
    }) catch return null;
    
    zb.defineFunction(module, .{
        .name = "greet",
        .func = greet,
        .doc = "Return a greeting",
    }) catch return null;
    
    return module;
}

fn greet(name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(
        zb.allocator,
        "Hello, {s}!",
        .{name},
    );
}
```

## Building

```bash
pip install .
```

## Usage

```python
import my_ext
print(my_ext.greet("World"))  # Hello, World!
```
````

---

## Phase 9: Polish & Release (Weeks 21-22)

### Objective
Final polish, optimization, and prepare for initial release.

### 9.1: Performance Optimization

**Tasks:**
1. Profile hot paths in function dispatch
2. Optimize type conversion routines
3. Minimize allocations in critical sections
4. Benchmark against nanobind/pybind11
5. Document performance characteristics

**Target Metrics:**
- Function call overhead: <50ns
- Type conversion: <100ns for primitives
- Object creation: <200ns
- Binary size: <200KB for minimal extension

### 9.2: Error Messages

**Enhance error reporting:**

```zig
pub fn formatError(
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const message = try std.fmt.allocPrint(
        py.allocator,
        fmt,
        args,
    );
    defer py.allocator.free(message);
    
    py.PyErr_SetString(py.PyExc_RuntimeError(), message.ptr);
}

// Example usage
if (value < 0) {
    try formatError(
        "Expected positive value, got {d}",
        .{value},
    );
    return error.ValueError;
}
```

### 9.3: Release Checklist

**Pre-release:**
- [ ] All tests passing on all platforms
- [ ] Documentation complete and reviewed
- [ ] Examples verified
- [ ] Benchmark results documented
- [ ] LICENSE file present
- [ ] CHANGELOG.md up to date
- [ ] README.md complete

**PyPI Release:**
- [ ] Version number set
- [ ] Wheels built for all platforms
- [ ] Source distribution created
- [ ] Upload to TestPyPI
- [ ] Verify installation from TestPyPI
- [ ] Upload to PyPI
- [ ] Tag release on GitHub

**Post-release:**
- [ ] Announcement on relevant forums
- [ ] Update documentation site
- [ ] Monitor issues
- [ ] Plan next version

### 9.4: Packaging for PyPI

**Final pyproject.toml:**

```toml
[build-system]
requires = ["wheel"]
build-backend = "_backend.backend"
backend-path = ["_backend"]

[project]
name = "zigbind"
version = "0.1.0"
description = "High-performance Python bindings for Zig"
readme = "README.md"
requires-python = ">=3.12"
license = {text = "BSD-3-Clause"}
authors = [
    {name = "Your Name", email = "your.email@example.com"}
]
keywords = ["zig", "python", "bindings", "extension"]
classifiers = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: BSD License",
    "Programming Language :: Python :: 3.12",
    "Programming Language :: Python :: 3.13",
    "Programming Language :: Zig",
    "Topic :: Software Development :: Libraries",
]

[project.urls]
Homepage = "https://github.com/yourusername/zigbind"
Documentation = "https://zigbind.readthedocs.io"
Repository = "https://github.com/yourusername/zigbind"
Issues = "https://github.com/yourusername/zigbind/issues"

[tool.cibuildwheel]
build = "cp312-* cp313-*"
skip = "*-musllinux_*"
archs = ["auto64"]

[tool.cibuildwheel.linux]
before-all = "curl -L https://ziglang.org/download/0.15.0/zig-linux-x86_64-0.15.0.tar.xz | tar -xJ"
environment = {PATH="/zig-linux-x86_64-0.15.0:$PATH"}

[tool.cibuildwheel.macos]
before-all = "brew install zig"

[tool.cibuildwheel.windows]
before-all = "choco install zig"
```

---

## Appendices

### A. Python Limited API Reference

**Key Functions Available:**
- Module: `PyModule_Create`, `PyModule_AddObject`
- Type: `PyType_FromSpec`, `PyType_Ready`
- Objects: `Py_INCREF`, `Py_DECREF`
- Integers: `PyLong_AsLongLong`, `PyLong_FromLongLong`
- Floats: `PyFloat_AsDouble`, `PyFloat_FromDouble`
- Strings: `PyUnicode_FromStringAndSize`, `PyUnicode_AsUTF8AndSize`
- Lists: `PyList_New`, `PyList_GetItem`, `PyList_SetItem`
- Dicts: `PyDict_New`, `PyDict_GetItem`, `PyDict_SetItem`
- Errors: `PyErr_SetString`, `PyErr_Occurred`, `PyErr_Clear`

**Limitations:**
- No direct struct member access
- No static type definitions
- Performance overhead (~10-20%)
- Must use `PyType_Spec` for types

### B. Zig Build System Integration

**Essential Build APIs:**
```zig
// Create shared library
const lib = b.addSharedLibrary(.{
    .name = "my_ext",
    .root_source_file = .{ .path = "src/my_ext.zig" },
    .target = target,
    .optimize = optimize,
});

// Link Python
lib.linkLibC();
lib.linkSystemLibrary("python3");

// Define macros
lib.defineCMacro("Py_LIMITED_API", "0x030C0000");

// Install
b.installArtifact(lib);
```

### C. Performance Comparison Targets

**Baseline Comparisons:**

| Operation | Target | nanobind | pybind11 |
|-----------|--------|----------|----------|
| Function call | <50ns | ~40ns | ~80ns |
| Int conversion | <20ns | ~15ns | ~30ns |
| Object creation | <200ns | ~150ns | ~300ns |
| Binary size | <200KB | ~100KB | ~500KB |

### D. Stable ABI Considerations

**Pros:**
- Single wheel for all Python 3.12+ versions
- Reduced maintenance burden
- Faster CI/CD pipelines
- Better for distribution

**Cons:**
- 10-20% performance penalty
- More complex implementation
- Cannot use internal CPython structures
- Requires Python 3.12+

**Decision:** Use stable ABI by default, with option to disable.

### E. Common Pitfalls

1. **Reference Counting**: Always pair `incref`/`decref`
2. **GIL Management**: Release GIL for long-running operations
3. **Error Handling**: Always check for NULL returns
4. **Memory Management**: Use consistent allocators
5. **Type Safety**: Validate Python types before conversion

### F. Future Enhancements

**Post-1.0 Features:**
- Buffer protocol support (NumPy interop)
- Iterator protocol
- Context manager support (`__enter__`/`__exit__`)
- Async/await support
- Multiple inheritance (if demand exists)
- JIT optimization hints
- Better IDE integration

---

## Success Criteria

### Week 1 Milestone
- ✅ Project compiles and installs via pip
- ✅ Hello world extension works
- ✅ Stable ABI verified

### Week 8 Milestone
- ✅ Basic function/class bindings working
- ✅ Type conversion for primitives
- ✅ Test suite passing

### Week 15 Milestone
- ✅ All advanced features implemented
- ✅ Comprehensive examples
- ✅ Performance benchmarks meet targets

### Week 22 Milestone (Release)
- ✅ Documentation complete
- ✅ CI/CD pipeline robust
- ✅ PyPI package published
- ✅ Wheels for all platforms

---

## Maintenance Plan

**Weekly Tasks:**
- Monitor GitHub issues
- Review pull requests
- Update dependencies
- Run security audits

**Monthly Tasks:**
- Performance profiling
- Documentation updates
- Blog posts / tutorials
- Community engagement

**Quarterly Tasks:**
- Major feature releases
- API review
- Dependency updates
- Security audits

---

## Conclusion

This plan provides a comprehensive roadmap for implementing zigbind from initial concept through to PyPI release. The phased approach ensures continuous progress with verifiable milestones, while the focus on stable ABI and Zig's native build system differentiates it from existing solutions.

Key success factors:
1. **Working from Day 1**: Always maintain a buildable, testable project
2. **Stable ABI**: Forward compatibility reduces maintenance burden
3. **Zig Build System**: Native integration simplifies user experience
4. **Comprehensive Testing**: Ensure reliability across platforms
5. **Clear Documentation**: Lower barrier to entry

The project is designed to be implemented by AI agents or developers following the plan sequentially, with each phase building on the previous one and including verification criteria.
