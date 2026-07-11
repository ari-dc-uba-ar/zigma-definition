const std = @import("std");

/// Expected-compile-error cases: each file in test/compile_errors must FAIL
/// to compile with a matching error (see Step.Compile.expect_errors). The
/// match is per line: a plain string must be the END of some error line; with
/// the /?/ wildcard the text before it must be the start of the line and the
/// text after it the end. For the messages of the framework the full message
/// is used (it is the end of the line); for native compiler messages whose
/// tail is not stable, the fragment file path is used as the start of the
/// line: the compilation must fail AT the marked expression of the fragment.
const compile_error_cases = [_]struct { file: []const u8, expected: []const u8 }{
    .{ .file = "record_unknown_type.zig", .expected = "unknown type 'inexistente'" },
    .{ .file = "record_unknown_property.zig", .expected = "unknown property 'colour'" },
    .{ .file = "record_is_name_false.zig", .expected = "is_name only admits true in a definition (false is the default)" },
    .{ .file = "instance_wrong_value_type.zig", .expected = "expected type 'i64', found '*const [6:0]u8'" },
    .{ .file = "instance_unknown_field.zig", .expected = "test\\compile_errors\\instance_unknown_field.zig:/?/" },
    .{ .file = "entity_pk_not_in_fields.zig", .expected = "pk field 'inexistente' is not a field of the entity" },
    .{ .file = "entity_pk_partially_wrong.zig", .expected = "pk field 'inexistente' is not a field of the entity" },
    .{ .file = "entity_fk_source_not_in_fields_list.zig", .expected = "source field 'inexistente' is not a field of the entity" },
    .{ .file = "entity_fk_source_not_in_fields_map.zig", .expected = "source field 'inexistente' is not a field of the entity" },
    .{ .file = "entity_uk_not_in_fields.zig", .expected = "uk field 'inexistente' is not a field of the entity" },
    .{ .file = "extract_pk_no_field.zig", .expected = "test\\compile_errors\\extract_pk_no_field.zig:/?/" },
    .{ .file = "system_fk_unknown_entity.zig", .expected = "unknown target entity 'inexistentes'" },
    .{ .file = "system_fk_partial_pk.zig", .expected = "target fields do not match the complete pk nor any uk of entity 'franjas'" },
    .{ .file = "info_fks_no_array_form.zig", .expected = "test\\compile_errors\\info_fks_no_array_form.zig:/?/" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigma_mod = b.addModule("zigma", .{
        .root_source_file = b.path("src/zigma.zig"),
        .target = target,
        .optimize = optimize,
    });

    const aida_mod = b.addModule("aida", .{
        .root_source_file = b.path("examples/aida.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigma", .module = zigma_mod },
        },
    });

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/aida_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigma", .module = zigma_mod },
                .{ .name = "aida", .module = aida_mod },
            },
        }),
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run tests (runtime and expected compile errors)");
    test_step.dependOn(&run_tests.step);

    for (compile_error_cases) |case| {
        const case_obj = b.addObject(.{
            .name = case.file[0 .. case.file.len - 4],
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("test/compile_errors/{s}", .{case.file})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zigma", .module = zigma_mod },
                    .{ .name = "aida", .module = aida_mod },
                },
            }),
        });
        case_obj.expect_errors = .{ .contains = case.expected };
        test_step.dependOn(&case_obj.step);
    }
}
