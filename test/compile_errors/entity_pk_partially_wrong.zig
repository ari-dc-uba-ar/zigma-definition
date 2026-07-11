//! expected: pk field 'inexistente' is not a field
//! (a wrong key among valid ones is also rejected)
const zigma = @import("zigma");
const aida = @import("aida");

comptime {
    _ = zigma.defineEntity(.{ .pk = .{ "materia", "inexistente" }, .fields = aida.materia });
}
