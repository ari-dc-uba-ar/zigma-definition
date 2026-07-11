//! expected: source field 'inexistente' is not a field
//! (list form: source and target share the name)
const zigma = @import("zigma");
const aida = @import("aida");

comptime {
    _ = zigma.defineEntity(.{
        .pk = .{"materia"},
        .fks = .{ .x = .{ .entity = "materias", .fields = .{"inexistente"} } },
        .fields = aida.materia,
    });
}
