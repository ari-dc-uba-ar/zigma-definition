//! expected: expected type
//! (after completion the array form is gone: fields is always the
//! source→target map, it cannot be used as a list)
const zigma = @import("zigma");
const aida = @import("aida");

comptime {
    const mesas_info = zigma.completeEntity(aida.mesas);
    const as_list: []const [:0]const u8 = mesas_info.fks.cursos.fields;
    _ = as_list;
}
