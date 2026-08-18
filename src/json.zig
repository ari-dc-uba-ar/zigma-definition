//! JSON writer for record instances and Def→Info schemas.
//! Record values follow the Zig field type (string, int, bool, nested struct).
//! `stringifyRecordSchema` writes `[{name,label},...]` from a completed record Info.
//! `stringifyEntitySchema` / `stringifyEntityCatalog` write entity Infos.
//! Field `storage` is the Zig shape used by the page (`text`/`integer`/`boolean`/
//! `object`), not the domain type name. A struct is `object` with nested `fields`.
//! `parseFieldValue` turns a cell string into that Zig type (structs as JSON objects;
//! string fields alias the cell, they are not copies from parse scratch).
//!
//! Generator: imports `zigma` only. Does not know any concrete system.

const std = @import("std");
const zigma = @import("zigma");

pub fn stringifyRecord(row: anytype, buf: []u8) error{NoSpaceLeft}![]const u8 {
    var pos: usize = 0;
    try writeJsonValue(buf, &pos, row);
    return buf[0..pos];
}

pub fn stringifyRecords(rows: anytype, buf: []u8) error{NoSpaceLeft}![]const u8 {
    var pos: usize = 0;
    try writeByte(buf, &pos, '[');
    for (rows, 0..) |row, i| {
        if (i != 0) try writeByte(buf, &pos, ',');
        const obj = try stringifyRecord(row, buf[pos..]);
        pos += obj.len;
    }
    try writeByte(buf, &pos, ']');
    return buf[0..pos];
}

pub fn stringifyRecordSchema(rec_info: anytype, buf: []u8) error{NoSpaceLeft}![]const u8 {
    var pos: usize = 0;
    try writeByte(buf, &pos, '[');
    inline for (@typeInfo(@TypeOf(rec_info)).@"struct".field_names, 0..) |name, i| {
        if (i != 0) try writeByte(buf, &pos, ',');
        try writeByte(buf, &pos, '{');
        try writeJsonString(buf, &pos, "name");
        try writeByte(buf, &pos, ':');
        try writeJsonString(buf, &pos, name);
        try writeByte(buf, &pos, ',');
        try writeJsonString(buf, &pos, "label");
        try writeByte(buf, &pos, ':');
        try writeJsonString(buf, &pos, @field(rec_info, name).label);
        try writeByte(buf, &pos, '}');
    }
    try writeByte(buf, &pos, ']');
    return buf[0..pos];
}

pub fn fieldStorage(comptime T: type) []const u8 {
    switch (@typeInfo(T)) {
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) return "text";
            @compileError("unsupported field type " ++ @typeName(T));
        },
        .int => return "integer",
        .bool => return "boolean",
        .@"struct" => return "object",
        else => @compileError("unsupported field type " ++ @typeName(T)),
    }
}

/// Cell string → `T`. Structs are JSON objects with `T`'s field names.
/// `[]const u8` values alias `bytes`, including string fields inside a struct
/// (the same contract as a top-level text cell). JSON strings that need an
/// unescape copy would live in parse scratch and are `error.InvalidValue`.
pub fn parseFieldValue(comptime T: type, bytes: []const u8) error{InvalidValue}!T {
    switch (@typeInfo(T)) {
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) return bytes;
            @compileError("unsupported field type " ++ @typeName(T));
        },
        .int => return std.fmt.parseInt(T, bytes, 10) catch error.InvalidValue,
        .bool => {
            if (std.mem.eql(u8, bytes, "true")) return true;
            if (std.mem.eql(u8, bytes, "false")) return false;
            return error.InvalidValue;
        },
        .@"struct" => |s| {
            if (s.is_tuple) @compileError("unsupported field type " ++ @typeName(T));
            var buf: [4096]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&buf);
            const value = std.json.parseFromSliceLeaky(T, fba.allocator(), bytes, .{
                .allocate = .alloc_if_needed,
            }) catch return error.InvalidValue;
            if (!slicesInsideInput(T, value, bytes)) return error.InvalidValue;
            return value;
        },
        else => @compileError("unsupported field type " ++ @typeName(T)),
    }
}

fn slicesInsideInput(comptime T: type, value: T, input: []const u8) bool {
    switch (@typeInfo(T)) {
        .pointer => |p| {
            if (p.size != .slice or p.child != u8) return true;
            const start = @intFromPtr(input.ptr);
            const ptr = @intFromPtr(value.ptr);
            return ptr >= start and ptr + value.len <= start + input.len;
        },
        .@"struct" => |st| {
            if (st.is_tuple) return true;
            inline for (st.field_names) |name| {
                if (!slicesInsideInput(@FieldType(T, name), @field(value, name), input)) return false;
            }
            return true;
        },
        else => return true,
    }
}

pub fn stringifyEntitySchema(comptime type_defs: anytype, entity_name: []const u8, comptime entity_def: anytype, buf: []u8) error{NoSpaceLeft}![]const u8 {
    const entity_info = zigma.completeEntity(entity_def);
    var pos: usize = 0;
    try writeByte(buf, &pos, '{');

    try writeJsonString(buf, &pos, "name");
    try writeByte(buf, &pos, ':');
    try writeJsonString(buf, &pos, entity_name);

    try writeByte(buf, &pos, ',');
    try writeJsonString(buf, &pos, "pk");
    try writeByte(buf, &pos, ':');
    try writeNameList(buf, &pos, entity_info.pk);

    try writeByte(buf, &pos, ',');
    try writeJsonString(buf, &pos, "uks");
    try writeByte(buf, &pos, ':');
    try writeUks(buf, &pos, entity_info.uks);

    try writeByte(buf, &pos, ',');
    try writeJsonString(buf, &pos, "fks");
    try writeByte(buf, &pos, ':');
    try writeFks(buf, &pos, entity_info.fks);

    try writeByte(buf, &pos, ',');
    try writeJsonString(buf, &pos, "fields");
    try writeByte(buf, &pos, ':');
    try writeEntityFields(buf, &pos, type_defs, entity_def.fields, entity_info.fields);

    try writeByte(buf, &pos, '}');
    return buf[0..pos];
}

pub fn stringifyEntityCatalog(comptime type_defs: anytype, comptime entity_defs: anytype, buf: []u8) error{NoSpaceLeft}![]const u8 {
    var pos: usize = 0;
    try writeByte(buf, &pos, '[');
    inline for (@typeInfo(@TypeOf(entity_defs)).@"struct".field_names, 0..) |name, i| {
        if (i != 0) try writeByte(buf, &pos, ',');
        const obj = try stringifyEntitySchema(type_defs, name, @field(entity_defs, name), buf[pos..]);
        pos += obj.len;
    }
    try writeByte(buf, &pos, ']');
    return buf[0..pos];
}

fn writeEntityFields(buf: []u8, pos: *usize, comptime type_defs: anytype, comptime rec: anytype, fields_info: anytype) error{NoSpaceLeft}!void {
    try writeByte(buf, pos, '[');
    inline for (@typeInfo(@TypeOf(fields_info)).@"struct".field_names, 0..) |name, i| {
        if (i != 0) try writeByte(buf, pos, ',');
        const info = @field(fields_info, name);
        const zig_type = @field(type_defs, @field(rec, name).type).Type;
        try writeByte(buf, pos, '{');
        try writeJsonString(buf, pos, "name");
        try writeByte(buf, pos, ':');
        try writeJsonString(buf, pos, name);
        try writeByte(buf, pos, ',');
        try writeJsonString(buf, pos, "label");
        try writeByte(buf, pos, ':');
        try writeJsonString(buf, pos, info.label);
        try writeByte(buf, pos, ',');
        try writeJsonString(buf, pos, "type");
        try writeByte(buf, pos, ':');
        try writeJsonString(buf, pos, info.type);
        try writeByte(buf, pos, ',');
        try writeJsonString(buf, pos, "storage");
        try writeByte(buf, pos, ':');
        try writeJsonString(buf, pos, fieldStorage(zig_type));
        if (@typeInfo(zig_type) == .@"struct") {
            try writeByte(buf, pos, ',');
            try writeNestedFields(buf, pos, zig_type);
        }
        try writeByte(buf, pos, '}');
    }
    try writeByte(buf, pos, ']');
}

fn writeNestedFields(buf: []u8, pos: *usize, comptime T: type) error{NoSpaceLeft}!void {
    const info = @typeInfo(T);
    try writeJsonString(buf, pos, "fields");
    try writeByte(buf, pos, ':');
    try writeByte(buf, pos, '[');
    inline for (info.@"struct".field_names, info.@"struct".field_types, 0..) |name, FieldType, i| {
        if (i != 0) try writeByte(buf, pos, ',');
        try writeByte(buf, pos, '{');
        try writeJsonString(buf, pos, "name");
        try writeByte(buf, pos, ':');
        try writeJsonString(buf, pos, name);
        try writeByte(buf, pos, ',');
        try writeJsonString(buf, pos, "storage");
        try writeByte(buf, pos, ':');
        try writeJsonString(buf, pos, fieldStorage(FieldType));
        if (@typeInfo(FieldType) == .@"struct") {
            try writeByte(buf, pos, ',');
            try writeNestedFields(buf, pos, FieldType);
        }
        try writeByte(buf, pos, '}');
    }
    try writeByte(buf, pos, ']');
}

fn writeUks(buf: []u8, pos: *usize, uks: anytype) error{NoSpaceLeft}!void {
    try writeByte(buf, pos, '{');
    inline for (@typeInfo(@TypeOf(uks)).@"struct".field_names, 0..) |name, i| {
        if (i != 0) try writeByte(buf, pos, ',');
        try writeJsonString(buf, pos, name);
        try writeByte(buf, pos, ':');
        try writeNameList(buf, pos, @field(uks, name));
    }
    try writeByte(buf, pos, '}');
}

fn writeFks(buf: []u8, pos: *usize, fks: anytype) error{NoSpaceLeft}!void {
    try writeByte(buf, pos, '{');
    inline for (@typeInfo(@TypeOf(fks)).@"struct".field_names, 0..) |name, i| {
        if (i != 0) try writeByte(buf, pos, ',');
        const fk = @field(fks, name);
        try writeJsonString(buf, pos, name);
        try writeByte(buf, pos, ':');
        try writeByte(buf, pos, '{');
        try writeJsonString(buf, pos, "entity");
        try writeByte(buf, pos, ':');
        try writeJsonString(buf, pos, fk.entity);
        try writeByte(buf, pos, ',');
        try writeJsonString(buf, pos, "fields");
        try writeByte(buf, pos, ':');
        try writeFkFields(buf, pos, fk.fields);
        try writeByte(buf, pos, '}');
    }
    try writeByte(buf, pos, '}');
}

fn writeFkFields(buf: []u8, pos: *usize, fields: anytype) error{NoSpaceLeft}!void {
    try writeByte(buf, pos, '{');
    inline for (@typeInfo(@TypeOf(fields)).@"struct".field_names, 0..) |name, i| {
        if (i != 0) try writeByte(buf, pos, ',');
        try writeJsonString(buf, pos, name);
        try writeByte(buf, pos, ':');
        try writeJsonString(buf, pos, nameSlice(@field(fields, name)));
    }
    try writeByte(buf, pos, '}');
}

fn writeNameList(buf: []u8, pos: *usize, list: anytype) error{NoSpaceLeft}!void {
    try writeByte(buf, pos, '[');
    switch (@typeInfo(@TypeOf(list))) {
        .array => {
            for (list, 0..) |name, i| {
                if (i != 0) try writeByte(buf, pos, ',');
                try writeJsonString(buf, pos, nameSlice(name));
            }
        },
        .pointer => |p| switch (p.size) {
            .slice => {
                for (list, 0..) |name, i| {
                    if (i != 0) try writeByte(buf, pos, ',');
                    try writeJsonString(buf, pos, nameSlice(name));
                }
            },
            .one => try writeNameList(buf, pos, list.*),
            else => @compileError("expected a list of names"),
        },
        .@"struct" => |s| {
            if (!s.is_tuple) @compileError("expected a list of names");
            inline for (s.field_names, 0..) |_, i| {
                if (i != 0) try writeByte(buf, pos, ',');
                try writeJsonString(buf, pos, nameSlice(list[i]));
            }
        },
        else => @compileError("expected a list of names"),
    }
    try writeByte(buf, pos, ']');
}

fn writeJsonValue(buf: []u8, pos: *usize, value: anytype) error{NoSpaceLeft}!void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) {
                try writeJsonString(buf, pos, value);
            } else if (p.size == .one) {
                switch (@typeInfo(p.child)) {
                    .array => |a| if (a.child == u8) {
                        try writeJsonString(buf, pos, value);
                    } else @compileError("unsupported json type " ++ @typeName(T)),
                    else => @compileError("unsupported json type " ++ @typeName(T)),
                }
            } else @compileError("unsupported json type " ++ @typeName(T));
        },
        .int => try writeInt(buf, pos, value),
        .bool => try writeRaw(buf, pos, if (value) "true" else "false"),
        .@"struct" => |s| {
            if (s.is_tuple) @compileError("unsupported json type " ++ @typeName(T));
            try writeByte(buf, pos, '{');
            inline for (s.field_names, 0..) |name, i| {
                if (i != 0) try writeByte(buf, pos, ',');
                try writeJsonString(buf, pos, name);
                try writeByte(buf, pos, ':');
                try writeJsonValue(buf, pos, @field(value, name));
            }
            try writeByte(buf, pos, '}');
        },
        else => @compileError("unsupported json type " ++ @typeName(T)),
    }
}

fn writeInt(buf: []u8, pos: *usize, value: anytype) error{NoSpaceLeft}!void {
    var tmp: [32]u8 = undefined;
    const slice = std.fmt.bufPrint(&tmp, "{d}", .{value}) catch return error.NoSpaceLeft;
    try writeRaw(buf, pos, slice);
}

fn nameSlice(name: anytype) []const u8 {
    const T = @TypeOf(name);
    switch (@typeInfo(T)) {
        .pointer => |p| {
            if (p.size == .slice) return name;
            if (p.size == .one) switch (@typeInfo(p.child)) {
                .array => |a| if (a.child == u8) return name,
                else => {},
            };
        },
        .array => |a| if (a.child == u8) return &name,
        else => {},
    }
    @compileError("expected a string, got " ++ @typeName(T));
}

fn writeJsonString(buf: []u8, pos: *usize, s: []const u8) error{NoSpaceLeft}!void {
    try writeByte(buf, pos, '"');
    try writeRaw(buf, pos, s);
    try writeByte(buf, pos, '"');
}

fn writeByte(buf: []u8, pos: *usize, byte: u8) error{NoSpaceLeft}!void {
    if (pos.* >= buf.len) return error.NoSpaceLeft;
    buf[pos.*] = byte;
    pos.* += 1;
}

fn writeRaw(buf: []u8, pos: *usize, bytes: []const u8) error{NoSpaceLeft}!void {
    if (pos.* + bytes.len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[pos.*..][0..bytes.len], bytes);
    pos.* += bytes.len;
}
