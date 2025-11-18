const std = @import("std");
const python_api = @import("python_api.zig");
const errors = @import("errors.zig");
const py = python_api.py;

/// Configuration for module creation
pub const ModuleConfig = struct {
    name: [:0]const u8,
    doc: [:0]const u8 = "",
    /// Module state size (-1 for no state)
    size: isize = -1,
};

/// Create a Python module with the given configuration
pub fn createModule(config: ModuleConfig) !*py.PyObject {
    // Allocate module def (needs to be persistent)
    var module_def = std.heap.c_allocator.create(py.PyModuleDef) catch {
        return errors.Error.MemoryError;
    };

    // Allocate methods array (start with sentinel, will grow as functions are added)
    const methods = std.heap.c_allocator.create(py.PyMethodDef) catch {
        std.heap.c_allocator.destroy(module_def);
        return errors.Error.MemoryError;
    };

    // Initialize sentinel
    methods.* = std.mem.zeroes(py.PyMethodDef);

    // Initialize module def
    module_def.* = std.mem.zeroes(py.PyModuleDef);
    module_def.m_base = py.PyModuleDef_Base{
        .ob_base = std.mem.zeroes(py.PyObject),
        .m_init = null,
        .m_index = 0,
        .m_copy = null,
    };
    module_def.m_name = config.name.ptr;
    module_def.m_doc = if (config.doc.len > 0) config.doc.ptr else null;
    module_def.m_size = config.size;
    module_def.m_methods = methods;

    const module = py.PyModule_Create(module_def);
    if (module == null) {
        std.heap.c_allocator.destroy(methods);
        std.heap.c_allocator.destroy(module_def);
        return errors.Error.RuntimeError;
    }

    return module.?;
}

/// Add a Python object to a module
pub fn addObject(module: *py.PyObject, name: [*:0]const u8, obj: *py.PyObject) !void {
    const result = py.PyModule_AddObject(module, name, obj);
    if (result < 0) {
        return errors.Error.RuntimeError;
    }
}

/// Add an integer constant to a module
pub fn addIntConstant(module: *py.PyObject, name: [*:0]const u8, value: c_long) !void {
    const result = py.PyModule_AddIntConstant(module, name, value);
    if (result < 0) {
        return errors.Error.RuntimeError;
    }
}

/// Add a string constant to a module
pub fn addStringConstant(module: *py.PyObject, name: [*:0]const u8, value: [*:0]const u8) !void {
    const result = py.PyModule_AddStringConstant(module, name, value);
    if (result < 0) {
        return errors.Error.RuntimeError;
    }
}
