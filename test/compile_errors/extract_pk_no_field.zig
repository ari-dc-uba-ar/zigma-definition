//! expected: no field named 'docente'
//! ('docente' is a field of cursos but is not part of the pk, so the
//! extracted record does not have it)
const zigma = @import("zigma");
const aida = @import("aida");

comptime {
    const cursos_pk_fields = zigma.extractPk(aida.cursos);
    _ = cursos_pk_fields.docente;
}
