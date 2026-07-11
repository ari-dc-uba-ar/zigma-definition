//! expected: expected type 'i64'
//! (the instance type is strongly typed: a string cannot be assigned to an
//! integer field)
const zigma = @import("zigma");
const aida = @import("aida");

comptime {
    const Cargo = zigma.RecordInstanceType(aida.type_defs, aida.cargo);
    const bad: Cargo = .{
        .cargo = "JTP",
        .denominacion = "Jefe de Trabajos Prácticos",
        .orden = "cuatro",
        .puede_dirigir = true,
    };
    _ = bad;
}
