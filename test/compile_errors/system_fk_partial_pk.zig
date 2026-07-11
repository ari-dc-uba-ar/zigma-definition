//! expected: do not match the complete pk nor any uk
//! (a fk that references only a part of a composite pk, and no uk, is
//! rejected: 'hora' is missing)
const zigma = @import("zigma");
const aida = @import("aida");

comptime {
    const franjas = zigma.defineEntity(.{
        .pk = .{ "dia", "hora" },
        .fields = zigma.record(aida.type_defs, .{
            .dia = .{ .type = "text" },
            .hora = .{ .type = "integer" },
        }),
    });
    const eventos = zigma.defineEntity(.{
        .pk = .{"evento"},
        .fks = .{ .franja = .{ .entity = "franjas", .fields = .{ .dia = "dia" } } },
        .fields = zigma.record(aida.type_defs, .{
            .evento = .{ .type = "text" },
            .dia = .{ .type = "text" },
        }),
    });
    _ = zigma.defineEntities(.{ .franjas = franjas, .eventos = eventos });
}
