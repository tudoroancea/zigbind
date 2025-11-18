const std = @import("std");
const python_api = @import("python_api.zig");
const errors = @import("errors.zig");
const type_caster = @import("type_caster.zig");
const py = python_api.py;

/// Define a Zig function as a Python callable
/// config should be an anonymous struct with fields: name, func, and optionally doc
pub fn defineFunction(module: *py.PyObject, comptime config: anytype) !void {
    const func = config.func;
    const FuncType = @TypeOf(func);
    const type_info = @typeInfo(FuncType);

    if (type_info != .@"fn") {
        @compileError("Expected function, got " ++ @typeName(FuncType));
    }

    // Create wrapper function that handles Python calling convention
    const wrapper = struct {
        fn call(
            self: ?*py.PyObject,
            args: ?*py.PyObject,
        ) callconv(.c) ?*py.PyObject {
            _ = self;

            // Parse arguments
            const zig_args = parseArgs(func, args orelse {
                errors.setException(errors.Error.RuntimeError);
                return null;
            }) catch |err| {
                errors.setException(err);
                return null;
            };

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

    // Allocate PyMethodDef (needs to persist)
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
    const pyfunc = py.PyCFunction_New(method_def, module);
    if (pyfunc == null) {
        std.heap.c_allocator.destroy(method_def);
        return errors.Error.RuntimeError;
    }

    // Add to module
    const result = py.PyModule_AddObject(module, config.name.ptr, pyfunc.?);
    if (result < 0) {
        std.heap.c_allocator.destroy(method_def);
        return errors.Error.RuntimeError;
    }
}
