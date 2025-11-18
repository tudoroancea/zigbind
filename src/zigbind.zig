const std = @import("std");
const python_api = @import("python_api.zig");

// Re-export Python C API
pub const py = python_api.py;

// Re-export commonly used types for backward compatibility
pub const PyObject = py.PyObject;
pub const PyMethodDef = py.PyMethodDef;
pub const PyModuleDef = py.PyModuleDef;
pub const PyModuleDef_Base = py.PyModuleDef_Base;

// Export new API modules
pub const errors = @import("errors.zig");
pub const type_caster = @import("type_caster.zig");
pub const module = @import("module.zig");
pub const function = @import("function.zig");

// Re-export ergonomic API at top level for convenience
pub const createModule = module.createModule;
pub const defineFunction = function.defineFunction;
pub const ModuleConfig = module.ModuleConfig;
pub const TypeCaster = type_caster.TypeCaster;
