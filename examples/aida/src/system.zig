//! Injected `system` for generators: aida Defs plus optional demo seeds.
//! Generators require `type_defs` and `entity_defs`; `seeds` is optional.

const aida = @import("aida.zig");

pub const type_defs = aida.type_defs;
pub const entity_defs = aida.entity_defs;

pub const seeds = .{
    .periodos = [_]aida.DefinedType(aida.periodo){
        .{ .periodo = "1C2024" },
        .{ .periodo = "2C2024" },
    },
    .materias = [_]aida.DefinedType(aida.materia){
        .{ .materia = "AlgoI", .denominacion = "Algoritmos y Programacion I" },
        .{ .materia = "AlgoII", .denominacion = "Algoritmos y Programacion II" },
        .{ .materia = "BD", .denominacion = "Bases de Datos" },
    },
    .docentes = [_]aida.DefinedType(aida.docente){
        .{
            .docente = "1",
            .apellido = "Perez",
            .nombres = "Ana",
            .cargo = "TIT",
            .email = "ana@example.com",
            .email_alternativo = "",
            .jefe = "",
        },
        .{
            .docente = "2",
            .apellido = "Gomez",
            .nombres = "Luis",
            .cargo = "JTP",
            .email = "luis@example.com",
            .email_alternativo = "",
            .jefe = "1",
        },
    },
    .alumnos = [_]aida.DefinedType(aida.alumno){
        .{ .alumno = "123", .apellido = "Garcia", .nombres = "Maria", .email = "maria@example.com" },
        .{ .alumno = "456", .apellido = "Lopez", .nombres = "Juan", .email = "juan@example.com" },
    },
    .cursos = [_]aida.DefinedType(aida.curso){
        .{ .periodo = "1C2024", .materia = "AlgoI", .docente = "1" },
    },
    .clases = [_]aida.DefinedType(aida.clase){
        .{
            .periodo = "1C2024",
            .materia = "AlgoI",
            .orden = 1,
            .fecha = .{ .@"año" = 2024, .mes = 3, .@"día" = 15 },
            .tema = "intro",
        },
    },
};
