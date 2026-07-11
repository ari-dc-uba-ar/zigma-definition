//! expected: unknown target entity 'inexistentes'
//! (a fk to an entity that is not part of the system is rejected)
const zigma = @import("zigma");
const aida = @import("aida");

comptime {
    const huerfanos = zigma.defineEntity(.{
        .pk = .{"x"},
        .fks = .{ .rota = .{ .entity = "inexistentes", .fields = .{ .x = "algo" } } },
        .fields = zigma.record(aida.type_defs, .{ .x = .{ .type = "text" } }),
    });
    _ = zigma.defineEntities(.{ .huerfanos = huerfanos });
}
