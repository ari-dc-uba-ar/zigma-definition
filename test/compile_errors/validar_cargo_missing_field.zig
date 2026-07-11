//! expected: an error at the call below (a missing field is rejected:
//! puede_dirigir is not given and the instance type has no defaults)
const aida = @import("aida");

comptime {
    _ = aida.validarCargo(.{ .cargo = "ADJ", .denominacion = "Adjunto", .orden = 2 });
}
