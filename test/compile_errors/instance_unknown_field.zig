//! expected: no field named 'inexistente'
//! (the completed record only has the fields of the definition)
const zigma = @import("zigma");
const aida = @import("aida");

comptime {
    const cargo_info = zigma.completeRecord(aida.cargo);
    _ = cargo_info.inexistente;
}
