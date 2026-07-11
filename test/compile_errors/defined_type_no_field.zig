//! expected: an error at the access below (fields outside the def cannot be
//! accessed)
const aida = @import("aida");

comptime {
    const titular: aida.DefinedType(aida.cargo) = .{
        .cargo = "TIT",
        .denominacion = "Titular",
        .orden = 1,
        .puede_dirigir = true,
    };
    _ = titular.inexistente;
}
