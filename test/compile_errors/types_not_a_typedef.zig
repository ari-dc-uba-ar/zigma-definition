//! expected: type 'text': must be a TypeDef
//! (the declaration-site check: the mistake is reported where the collection
//! is defined, not where it is first used)
const zigma = @import("zigma");

comptime {
    _ = zigma.defineTypes(.{ .text = 42 });
}
