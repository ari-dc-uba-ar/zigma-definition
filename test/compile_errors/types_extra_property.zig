//! expected: type 'fecha': must be a TypeDef
//! (a struct that is not exactly the shape of TypeDef is rejected too)
const zigma = @import("zigma");

comptime {
    _ = zigma.defineTypes(.{ .fecha = .{ .Type = f64, .extra = true } });
}
