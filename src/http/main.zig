//! Generic HTTP backend: in-memory lists per entity of the injected `system`.
//! `system` must export `type_defs` and `entity_defs`. Optional `seeds` is a
//! struct of row arrays keyed by entity name.

const std = @import("std");
const zigma = @import("zigma");
const system = @import("system");
const zigma_json = @import("zigma_json");

const port: u16 = 8080;
const entity_names = @typeInfo(@TypeOf(system.entity_defs)).@"struct".field_names;
const entity_count = entity_names.len;

const cors_origin = std.http.Header{
    .name = "Access-Control-Allow-Origin",
    .value = "*",
};

const cors_methods = std.http.Header{
    .name = "Access-Control-Allow-Methods",
    .value = "POST, PUT, GET, OPTIONS",
};

const cors_headers = std.http.Header{
    .name = "Access-Control-Allow-Headers",
    .value = "Content-Type",
};

const json_content_type = std.http.Header{
    .name = "Content-Type",
    .value = "application/json",
};

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const gpa = debug_allocator.allocator();

    var lists: [entity_count]std.ArrayList([]const u8) = undefined;
    for (&lists) |*list| list.* = .empty;
    defer {
        for (&lists) |*list| {
            for (list.items) |item| gpa.free(item);
            list.deinit(gpa);
        }
    }
    try seed(gpa, &lists);

    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const address = try std.Io.net.IpAddress.parseIp4("0.0.0.0", port);
    var tcp_server = try address.listen(io, .{ .reuse_address = true });
    defer tcp_server.deinit(io);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("backend running on port {d}...\n", .{port});
    try stdout.flush();

    while (true) {
        const stream = try tcp_server.accept(io);
        handleConnection(gpa, io, stdout, stream, &lists) catch |err| {
            std.debug.print("connection error: {t}\n", .{err});
        };
        stream.close(io);
    }
}

fn seed(gpa: std.mem.Allocator, lists: *[entity_count]std.ArrayList([]const u8)) !void {
    if (!@hasDecl(system, "seeds")) return;
    inline for (entity_names, 0..) |name, i| {
        if (@hasField(@TypeOf(system.seeds), name)) {
            for (@field(system.seeds, name)) |row| {
                try appendJson(gpa, &lists[i], row);
            }
        }
    }
}

fn appendJson(gpa: std.mem.Allocator, list: *std.ArrayList([]const u8), row: anytype) !void {
    var buf: [8192]u8 = undefined;
    const json = try zigma_json.stringifyRecord(row, &buf);
    try list.append(gpa, try gpa.dupe(u8, json));
}

fn handleConnection(
    gpa: std.mem.Allocator,
    io: std.Io,
    stdout: *std.Io.Writer,
    stream: std.Io.net.Stream,
    lists: *[entity_count]std.ArrayList([]const u8),
) !void {
    var send_buffer: [4096]u8 = undefined;
    var recv_buffer: [4096]u8 = undefined;
    var connection_reader = stream.reader(io, &recv_buffer);
    var connection_writer = stream.writer(io, &send_buffer);
    var server: std.http.Server = .init(&connection_reader.interface, &connection_writer.interface);

    while (true) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => return err,
        };
        try handleRequest(gpa, stdout, &request, lists);
    }
}

fn handleRequest(
    gpa: std.mem.Allocator,
    stdout: *std.Io.Writer,
    request: *std.http.Server.Request,
    lists: *[entity_count]std.ArrayList([]const u8),
) !void {
    switch (request.head.method) {
        .OPTIONS => try request.respond("", .{
            .extra_headers = &.{ cors_origin, cors_methods, cors_headers },
        }),
        .GET => try handleGet(stdout, request, lists),
        .POST => try handleWrite(gpa, stdout, request, lists, .post),
        .PUT => try handleWrite(gpa, stdout, request, lists, .put),
        else => try request.respond("Not Implemented", .{
            .status = .not_implemented,
            .extra_headers = &.{cors_origin},
        }),
    }
}

fn entityNameOf(path: []const u8) ?[]const u8 {
    if (path.len < 2 or path[0] != '/') return null;
    const rest = path[1..];
    if (rest.len == 0 or std.mem.indexOfScalar(u8, rest, '/') != null) return null;
    return rest;
}

fn listFor(lists: *[entity_count]std.ArrayList([]const u8), name: []const u8) ?*std.ArrayList([]const u8) {
    inline for (entity_names, 0..) |n, i| {
        if (std.mem.eql(u8, name, n)) return &lists[i];
    }
    return null;
}

fn joinJsonArray(items: []const []const u8, buf: []u8) error{NoSpaceLeft}![]const u8 {
    var pos: usize = 0;
    if (pos >= buf.len) return error.NoSpaceLeft;
    buf[pos] = '[';
    pos += 1;
    for (items, 0..) |item, i| {
        if (i != 0) {
            if (pos >= buf.len) return error.NoSpaceLeft;
            buf[pos] = ',';
            pos += 1;
        }
        if (pos + item.len > buf.len) return error.NoSpaceLeft;
        @memcpy(buf[pos..][0..item.len], item);
        pos += item.len;
    }
    if (pos >= buf.len) return error.NoSpaceLeft;
    buf[pos] = ']';
    pos += 1;
    return buf[0..pos];
}

fn handleGet(
    stdout: *std.Io.Writer,
    request: *std.http.Server.Request,
    lists: *[entity_count]std.ArrayList([]const u8),
) !void {
    try stdout.print("\n--- INCOMING HTTP GET REQUEST: {s} ---\n", .{request.head.target});
    try stdout.flush();

    const name = entityNameOf(request.head.target) orelse {
        try request.respond("Not Found", .{ .status = .not_found, .extra_headers = &.{cors_origin} });
        return;
    };
    const list = listFor(lists, name) orelse {
        try request.respond("Not Found", .{ .status = .not_found, .extra_headers = &.{cors_origin} });
        return;
    };

    var json_buf: [65536]u8 = undefined;
    const json = try joinJsonArray(list.items, &json_buf);
    try request.respond(json, .{
        .extra_headers = &.{ json_content_type, cors_origin },
    });
}

fn valuesEqual(a: anytype, b: @TypeOf(a)) bool {
    switch (@typeInfo(@TypeOf(a))) {
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) return std.mem.eql(u8, a, b);
        },
        .int, .bool => return a == b,
        .@"struct" => {
            inline for (@typeInfo(@TypeOf(a)).@"struct".field_names) |name| {
                if (!valuesEqual(@field(a, name), @field(b, name))) return false;
            }
            return true;
        },
        else => {},
    }
    return false;
}

fn pkEqual(comptime entity: anytype, a: anytype, b: anytype) bool {
    inline for (entity.pk) |name| {
        if (!valuesEqual(@field(a, name), @field(b, name))) return false;
    }
    return true;
}

fn replaceByPk(
    gpa: std.mem.Allocator,
    list: *std.ArrayList([]const u8),
    comptime entity: anytype,
    new_row: anytype,
) !bool {
    const Row = @TypeOf(new_row);
    var buf: [8192]u8 = undefined;
    const json = try zigma_json.stringifyRecord(new_row, &buf);
    for (list.items, 0..) |old_json, i| {
        const parsed = std.json.parseFromSlice(Row, gpa, old_json, .{}) catch continue;
        defer parsed.deinit();
        if (pkEqual(entity, parsed.value, new_row)) {
            gpa.free(old_json);
            list.items[i] = try gpa.dupe(u8, json);
            return true;
        }
    }
    return false;
}

fn handleWrite(
    gpa: std.mem.Allocator,
    stdout: *std.Io.Writer,
    request: *std.http.Server.Request,
    lists: *[entity_count]std.ArrayList([]const u8),
    kind: enum { post, put },
) !void {
    var path_buf: [1024]u8 = undefined;
    if (request.head.target.len > path_buf.len) return error.TargetTooLong;
    const path = path_buf[0..request.head.target.len];
    @memcpy(path, request.head.target);

    const label = if (kind == .post) "POST" else "PUT";
    try stdout.print("\n--- INCOMING HTTP {s} REQUEST ---\n", .{label});
    try stdout.print("Path: {s}\n", .{path});
    try stdout.print("Headers:\n", .{});
    var headers = request.iterateHeaders();
    while (headers.next()) |header| {
        if (headers.is_trailer) break;
        try stdout.print("{s}: {s}\n", .{ header.name, header.value });
    }
    try stdout.print("\nBody Payload:\n", .{});

    var body_buf: [4096]u8 = undefined;
    const body_reader = try request.readerExpectContinue(&body_buf);
    const body = try body_reader.allocRemaining(gpa, .unlimited);
    defer gpa.free(body);

    if (std.json.parseFromSlice(std.json.Value, gpa, body, .{})) |parsed| {
        defer parsed.deinit();
        try stdout.print("{f}\n", .{std.json.fmt(parsed.value, .{ .whitespace = .indent_2 })});
    } else |_| {
        try stdout.print("{s}\n", .{body});
    }
    try stdout.print("----------------------------------\n\n", .{});
    try stdout.flush();

    const name = entityNameOf(path) orelse {
        try request.respond("Not Found", .{ .status = .not_found, .extra_headers = &.{cors_origin} });
        return;
    };

    var matched = false;
    @setEvalBranchQuota(10000);
    inline for (entity_names, 0..) |n, i| {
        if (std.mem.eql(u8, name, n)) {
            matched = true;
            const entity = @field(system.entity_defs, n);
            const Row = zigma.RecordInstanceType(system.type_defs, entity.fields);
            const parsed = std.json.parseFromSlice(Row, gpa, body, .{}) catch {
                try request.respond("{\"status\":\"invalid\"}", .{
                    .status = .bad_request,
                    .extra_headers = &.{ json_content_type, cors_origin },
                });
                return;
            };
            defer parsed.deinit();
            if (kind == .post) {
                try appendJson(gpa, &lists[i], parsed.value);
            } else {
                const replaced = try replaceByPk(gpa, &lists[i], entity, parsed.value);
                if (!replaced) {
                    try request.respond("{\"status\":\"not found\"}", .{
                        .status = .not_found,
                        .extra_headers = &.{ json_content_type, cors_origin },
                    });
                    return;
                }
            }
        }
    }
    if (!matched) {
        try request.respond("Not Found", .{ .status = .not_found, .extra_headers = &.{cors_origin} });
        return;
    }

    try request.respond("{\"status\": \"received\"}", .{
        .extra_headers = &.{ json_content_type, cors_origin },
    });
}
