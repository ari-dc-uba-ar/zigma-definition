const std = @import("std");
const zigma = @import("zigma");
const aida = @import("aida");

extern "env" fn js_send_post(ptr: [*]const u8, len: usize) void;

const MateriaRow = zigma.RecordInstanceType(aida.type_defs, aida.materia);

export fn create_materia_request() void {
    const new_materia: MateriaRow = .{
        .materia = "AlgoI",
        .denominacion = "Algoritmos y Programacion I",
    };

    // Construct the JSON payload directly using bufPrint to ensure 100%
    // compatibility with Zig 0.16 string formatting without relying on changing json internals.
    var buf: [256]u8 = undefined;
    const json_slice = std.fmt.bufPrint(&buf, "{{\"materia\":\"{s}\",\"denominacion\":\"{s}\"}}", .{
        new_materia.materia,
        new_materia.denominacion,
    }) catch return;

    // Send payload to JavaScript fetch wrapper
    js_send_post(json_slice.ptr, json_slice.len);
}
