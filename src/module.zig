const std = @import("std");
const python_api = @import("python_api.zig");
const errors = @import("errors.zig");
const type_caster = @import("type_caster.zig");
const py = python_api.py;

/// Configuration for module creation
pub const ModuleConfig = struct {
    name: [:0]const u8,
    doc: [:0]const u8 = "",
    /// Module state size (-1 for no state)
    size: isize = -1,
};

/// Python module wrapper with ergonomic method-based API
pub const Module = struct {
    obj: *py.PyObject,

    /// Create a Python module with the given configuration
    /// NOTE: The returned module owns persistent allocations (module_def, methods)
    /// that must outlive the Python module object and are intentionally never freed.
    /// This is standard for Python C extensions - these structures persist until process exit.
    pub fn init(config: ModuleConfig) !Module {
        // Allocate module def (needs to be persistent for module lifetime)
        var module_def = std.heap.c_allocator.create(py.PyModuleDef) catch {
            return errors.Error.MemoryError;
        };

        // Allocate methods array (needs to be persistent for module lifetime)
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

        return Module{ .obj = module.? };
    }

    /// Define a Zig function as a Python callable on this module
    /// config should be an anonymous struct with fields: name, func, and optionally doc
    pub fn def(self: *Module, comptime config: anytype) !void {
        const func = config.func;
        const FuncType = @TypeOf(func);
        const type_info = @typeInfo(FuncType);

        if (type_info != .@"fn") {
            @compileError("Expected function, got " ++ @typeName(FuncType));
        }

        // Create wrapper function that handles Python calling convention
        const wrapper = struct {
            fn call(
                _self: ?*py.PyObject,
                args: ?*py.PyObject,
            ) callconv(.c) ?*py.PyObject {
                _ = _self;

                // Parse arguments
                const zig_args = parseArgs(func, args orelse {
                    errors.setException(errors.Error.RuntimeError);
                    return null;
                }) catch |err| {
                    errors.setException(err);
                    return null;
                };
                // Defer cleanup of any allocated slices in zig_args
                defer cleanupArgs(func, zig_args);

                // Call the Zig function and convert result
                const FType = @TypeOf(func);
                const return_type = @typeInfo(FType).@"fn".return_type.?;
                const return_info = @typeInfo(return_type);

                if (return_info == .error_union) {
                    // Function returns error union
                    const result = @call(.auto, func, zig_args) catch |err| {
                        errors.setException(err);
                        return null;
                    };
                    return convertResult(result) catch |err| {
                        errors.setException(err);
                        return null;
                    };
                } else {
                    // Function returns non-error value
                    const result = @call(.auto, func, zig_args);
                    return convertResult(result) catch |err| {
                        errors.setException(err);
                        return null;
                    };
                }
            }

            fn parseArgs(
                comptime f: anytype,
                args: *py.PyObject,
            ) !ArgsType(f) {
                const FType = @TypeOf(f);
                const f_info = @typeInfo(FType).@"fn";

                // Get number of arguments
                const n_args = py.PyTuple_Size(args);
                if (n_args < 0) {
                    return errors.Error.RuntimeError;
                }

                // Check argument count matches
                if (n_args != f_info.params.len) {
                    return errors.Error.TypeError;
                }

                var result: ArgsType(f) = undefined;

                inline for (f_info.params, 0..) |param, i| {
                    const ParamType = param.type orelse {
                        @compileError("Cannot infer parameter type");
                    };

                    // Get argument from tuple
                    const py_arg = py.PyTuple_GetItem(args, @intCast(i));
                    if (py_arg == null) {
                        return errors.Error.RuntimeError;
                    }

                    // Convert to Zig type
                    result[i] = try type_caster.TypeCaster(ParamType).fromPython(py_arg.?);
                }

                return result;
            }

            fn convertResult(result: anytype) !*py.PyObject {
                const ResultType = @TypeOf(result);
                return try type_caster.TypeCaster(ResultType).toPython(result);
            }

            fn cleanupArgs(comptime f: anytype, args: anytype) void {
                // Clean up any dynamically allocated slices in the arguments
                // This is important for memory management: slices allocated by
                // fromPythonList must be freed after the function returns
                const FType = @TypeOf(f);
                const f_info = @typeInfo(FType).@"fn";

                inline for (f_info.params, 0..) |param, i| {
                    const ParamType = param.type orelse {
                        @compileError("Cannot infer parameter type");
                    };
                    // Free if this parameter is a slice
                    type_caster.freeIfSlice(ParamType, args[i]);
                }
            }

            fn ArgsType(comptime f: anytype) type {
                const FType = @TypeOf(f);
                const f_info = @typeInfo(FType).@"fn";

                var param_types: [f_info.params.len]type = undefined;
                inline for (f_info.params, 0..) |param, i| {
                    param_types[i] = param.type orelse {
                        @compileError("Cannot infer parameter type");
                    };
                }

                return std.meta.Tuple(&param_types);
            }
        };

        // Allocate PyMethodDef (needs to persist for function lifetime)
        // NOTE: This allocation is intentionally never freed. The PyCFunction object
        // holds a pointer to this structure and it must remain valid for the module's lifetime.
        // This is standard Python C extension behavior.
        const method_def = std.heap.c_allocator.create(py.PyMethodDef) catch {
            return errors.Error.MemoryError;
        };

        method_def.* = py.PyMethodDef{
            .ml_name = config.name.ptr,
            .ml_meth = @ptrCast(&wrapper.call),
            .ml_flags = py.METH_VARARGS,
            .ml_doc = if (config.doc.len > 0) config.doc.ptr else null,
        };

        // Create PyCFunction
        const pyfunc = py.PyCFunction_New(method_def, self.obj);
        if (pyfunc == null) {
            std.heap.c_allocator.destroy(method_def);
            return errors.Error.RuntimeError;
        }

        // Add to module
        // NOTE: PyModule_AddObject steals reference on success (returns 0)
        // but does NOT steal on failure (returns -1)
        const result = py.PyModule_AddObject(self.obj, config.name.ptr, pyfunc.?);
        if (result < 0) {
            py.Py_DecRef(pyfunc.?); // Must decref on failure since ref wasn't stolen
            std.heap.c_allocator.destroy(method_def);
            return errors.Error.RuntimeError;
        }
    }

    /// Add a Python object to this module
    /// NOTE: Takes ownership of obj - steals reference on success, caller must Py_DECREF on failure
    pub fn addObject(self: *Module, name: [*:0]const u8, obj: *py.PyObject) !void {
        const result = py.PyModule_AddObject(self.obj, name, obj);
        if (result < 0) {
            py.Py_DecRef(obj); // Must decref on failure since ref wasn't stolen
            return errors.Error.RuntimeError;
        }
    }

    /// Add an integer constant to this module
    pub fn addIntConstant(self: *Module, name: [*:0]const u8, value: c_long) !void {
        const result = py.PyModule_AddIntConstant(self.obj, name, value);
        if (result < 0) {
            return errors.Error.RuntimeError;
        }
    }

    /// Add a string constant to this module
    pub fn addStringConstant(self: *Module, name: [*:0]const u8, value: [*:0]const u8) !void {
        const result = py.PyModule_AddStringConstant(self.obj, name, value);
        if (result < 0) {
            return errors.Error.RuntimeError;
        }
    }

    /// Get the underlying PyObject for PyInit_* return
    pub fn pyobject(self: Module) *py.PyObject {
        return self.obj;
    }
};
