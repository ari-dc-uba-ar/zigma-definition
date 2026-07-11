//! expected: source field 'inexistente' is not a field
//! (map form: the source is the key)
const zigma = @import("zigma");
const aida = @import("aida");

comptime {
    _ = zigma.defineEntity(.{
        .pk = .{"materia"},
        .fks = .{ .x = .{ .entity = "materias", .fields = .{ .inexistente = "materia" } } },
        .fields = aida.materia,
    });
}
