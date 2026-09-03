const std = @import("std");

fn at(comptime file: []const u8) []const u8 {
    const sep = std.fs.path.sep_str;
    return std.fmt.comptimePrint("test{s}compile_errors{s}{s}:/?/", .{ sep, sep, file });
}

const compile_error_cases = [_]struct { file: []const u8, expected: []const u8 }{
    .{ .file = "types_not_a_typedef.zig", .expected = "type 'text': must be a TypeDef (like zigma.TypeDef{ .Type = i64 })" },
    .{ .file = "types_extra_property.zig", .expected = "type 'fecha': must be a TypeDef (like zigma.TypeDef{ .Type = i64 })" },
    .{ .file = "record_unknown_type.zig", .expected = "unknown type 'inexistente'" },
    .{ .file = "record_unknown_property.zig", .expected = "unknown property 'colour'" },
    .{ .file = "record_is_name_false.zig", .expected = "is_name only admits true in a definition (false is the default)" },
    .{ .file = "instance_wrong_value_type.zig", .expected = "expected type 'i64', found '*const [6:0]u8'" },
    .{ .file = "instance_unknown_field.zig", .expected = at("instance_unknown_field.zig") },
    .{ .file = "entity_pk_not_in_fields.zig", .expected = "pk field 'inexistente' is not a field of the entity" },
    .{ .file = "entity_pk_partially_wrong.zig", .expected = "pk field 'inexistente' is not a field of the entity" },
    .{ .file = "entity_fk_source_not_in_fields_list.zig", .expected = "source field 'inexistente' is not a field of the entity" },
    .{ .file = "entity_fk_source_not_in_fields_map.zig", .expected = "source field 'inexistente' is not a field of the entity" },
    .{ .file = "entity_uk_not_in_fields.zig", .expected = "uk field 'inexistente' is not a field of the entity" },
    .{ .file = "extract_pk_no_field.zig", .expected = at("extract_pk_no_field.zig") },
    .{ .file = "system_fk_unknown_entity.zig", .expected = "unknown target entity 'inexistentes'" },
    .{ .file = "system_fk_partial_pk.zig", .expected = "target fields do not match the complete pk nor any uk of entity 'franjas'" },
    .{ .file = "info_fks_no_array_form.zig", .expected = at("info_fks_no_array_form.zig") },
    .{ .file = "defined_type_wrong_field_type.zig", .expected = "expected type 'i64', found '*const [1:0]u8'" },
    .{ .file = "validar_cargo_missing_field.zig", .expected = at("validar_cargo_missing_field.zig") },
    .{ .file = "defined_type_no_field.zig", .expected = at("defined_type_no_field.zig") },
};

/// Source files of this package, so a consumer can compile the generators.
pub const PackageFiles = struct {
    zigma: std.Build.LazyPath,
    json: std.Build.LazyPath,
    frontend_main: std.Build.LazyPath,
    frontend_js: std.Build.LazyPath,
    frontend_html: std.Build.LazyPath,
    http: std.Build.LazyPath,
};

pub fn filesHere(b: *std.Build) PackageFiles {
    return .{
        .zigma = b.path("src/zigma.zig"),
        .json = b.path("src/json.zig"),
        .frontend_main = b.path("src/frontend/main.zig"),
        .frontend_js = b.path("src/frontend/main.js"),
        .frontend_html = b.path("src/frontend/index.html"),
        .http = b.path("src/http/main.zig"),
    };
}

pub fn filesFromDependency(dep: *std.Build.Dependency) PackageFiles {
    return .{
        .zigma = dep.path("src/zigma.zig"),
        .json = dep.path("src/json.zig"),
        .frontend_main = dep.path("src/frontend/main.zig"),
        .frontend_js = dep.path("src/frontend/main.js"),
        .frontend_html = dep.path("src/frontend/index.html"),
        .http = dep.path("src/http/main.zig"),
    };
}

pub const AppOptions = struct {
    files: PackageFiles,
    system_root: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    /// Optional consumer map `domain type → widget`; installed as `widgets.js`.
    widgets_js: ?std.Build.LazyPath = null,
    /// Optional browser tab title; installed as generated `title.js`.
    title: ?[]const u8 = null,
};

pub const App = struct {
    backend: *std.Build.Step.Compile,
    frontend: *std.Build.Step.Compile,
    run_backend: *std.Build.Step.Run,
};

fn zigmaModule(
    b: *std.Build,
    files: PackageFiles,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = files.zigma,
        .target = target,
        .optimize = optimize,
    });
}

fn jsonModule(
    b: *std.Build,
    files: PackageFiles,
    zigma: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = files.json,
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigma", .module = zigma },
        },
    });
}

fn systemModule(
    b: *std.Build,
    system_root: std.Build.LazyPath,
    zigma: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = system_root,
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigma", .module = zigma },
        },
    });
}

/// Compile a native HTTP backend and a WASM frontend from the same `system` file
/// (`type_defs` + `entity_defs`; optional `seeds`). Each artifact gets its own
/// `zigma` / `zigma_json` / `system` module instance so native and wasm32 do not share a target.
pub fn addApp(b: *std.Build, opts: AppOptions) App {
    const files = opts.files;

    const zigma_native = zigmaModule(b, files, opts.target, opts.optimize);
    const json_native = jsonModule(b, files, zigma_native, opts.target, opts.optimize);
    const system_native = systemModule(b, opts.system_root, zigma_native, opts.target, opts.optimize);

    const backend = b.addExecutable(.{
        .name = "backend",
        .root_module = b.createModule(.{
            .root_source_file = files.http,
            .target = opts.target,
            .optimize = opts.optimize,
            .imports = &.{
                .{ .name = "zigma", .module = zigma_native },
                .{ .name = "zigma_json", .module = json_native },
                .{ .name = "system", .module = system_native },
            },
        }),
    });
    b.installArtifact(backend);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_optimize: std.builtin.OptimizeMode = .small;

    const zigma_wasm = zigmaModule(b, files, wasm_target, wasm_optimize);
    const json_wasm = jsonModule(b, files, zigma_wasm, wasm_target, wasm_optimize);
    const system_wasm = systemModule(b, opts.system_root, zigma_wasm, wasm_target, wasm_optimize);

    const frontend = b.addExecutable(.{
        .name = "frontend",
        .root_module = b.createModule(.{
            .root_source_file = files.frontend_main,
            .target = wasm_target,
            .optimize = wasm_optimize,
            .imports = &.{
                .{ .name = "zigma", .module = zigma_wasm },
                .{ .name = "zigma_json", .module = json_wasm },
                .{ .name = "system", .module = system_wasm },
            },
        }),
    });
    frontend.entry = .disabled;
    frontend.rdynamic = true;
    frontend.export_memory = true;

    const frontend_dir: std.Build.InstallDir = .{ .custom = "frontend" };
    const install_wasm = b.addInstallArtifact(frontend, .{
        .dest_dir = .{ .override = frontend_dir },
    });
    b.getInstallStep().dependOn(&install_wasm.step);

    const frontend_step = b.step("frontend", "Build and install the WASM frontend");
    frontend_step.dependOn(&install_wasm.step);

    const install_js = b.addInstallFileWithDir(files.frontend_js, frontend_dir, "main.js");
    const install_html = b.addInstallFileWithDir(files.frontend_html, frontend_dir, "index.html");
    b.getInstallStep().dependOn(&install_js.step);
    b.getInstallStep().dependOn(&install_html.step);
    frontend_step.dependOn(&install_js.step);
    frontend_step.dependOn(&install_html.step);

    const title_js = b.addWriteFiles().add(
        "title.js",
        b.fmt("document.title = {f};\n", .{std.json.fmt(opts.title orelse "", .{})}),
    );
    const install_title = b.addInstallFileWithDir(title_js, frontend_dir, "title.js");
    b.getInstallStep().dependOn(&install_title.step);
    frontend_step.dependOn(&install_title.step);

    if (opts.widgets_js) |widgets_js| {
        const install_widgets = b.addInstallFileWithDir(widgets_js, frontend_dir, "widgets.js");
        b.getInstallStep().dependOn(&install_widgets.step);
        frontend_step.dependOn(&install_widgets.step);
    }

    const run_backend = b.addRunArtifact(backend);
    run_backend.has_side_effects = true;
    const backend_step = b.step("backend", "Run the HTTP backend generated from the system module");
    backend_step.dependOn(&run_backend.step);
    const dummy_step = b.step("dummy", "Run the HTTP backend (alias of backend)");
    dummy_step.dependOn(&run_backend.step);

    return .{
        .backend = backend,
        .frontend = frontend,
        .run_backend = run_backend,
    };
}

/// Same as `addApp`, using paths from a `zigma_definition` dependency.
pub fn addAppFromDep(
    b: *std.Build,
    dep: *std.Build.Dependency,
    opts: struct {
        system_root: std.Build.LazyPath,
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        widgets_js: ?std.Build.LazyPath = null,
        title: ?[]const u8 = null,
    },
) App {
    return addApp(b, .{
        .files = filesFromDependency(dep),
        .system_root = opts.system_root,
        .target = opts.target,
        .optimize = opts.optimize,
        .widgets_js = opts.widgets_js,
        .title = opts.title,
    });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigma_mod = b.addModule("zigma", .{
        .root_source_file = b.path("src/zigma.zig"),
        .target = target,
        .optimize = optimize,
    });
    const aida_mod = b.addModule("aida", .{
        .root_source_file = b.path("examples/aida/src/aida.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zigma", .module = zigma_mod },
        },
    });
    const zigma_json_mod = b.addModule("zigma_json", .{
        .root_source_file = b.path("src/json.zig"),
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

    const json_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/json_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigma", .module = zigma_mod },
                .{ .name = "aida", .module = aida_mod },
                .{ .name = "zigma_json", .module = zigma_json_mod },
            },
        }),
    });
    const run_json_tests = b.addRunArtifact(json_tests);

    const test_step = b.step("test", "Run tests (runtime and expected compile errors)");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_json_tests.step);

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
