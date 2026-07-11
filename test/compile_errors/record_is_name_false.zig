//! expected: is_name only admits true
//! (in a Def only `.is_name = true` can be written; false is the default and
//! it is made explicit by the completion, like `isName?: true` in TypeScript)
const zigma = @import("zigma");
const aida = @import("aida");

comptime {
    _ = zigma.record(aida.type_defs, .{
        .campo = .{ .type = "text", .is_name = false },
    });
}
