//! Generic WASM frontend. The host build injects a `system` module that
//! exports `type_defs` and `entity_defs`.

const std = @import("std");
const zigma = @import("zigma");
const system = @import("system");
const zigma_json = @import("zigma_json");

extern "env" fn js_send_post(ptr: [*]const u8, len: usize) void;

const type_defs = system.type_defs;
const entity_defs = system.entity_defs;
const entity_names = @typeInfo(@TypeOf(entity_defs)).@"struct".field_names;

fn maxFieldCount() usize {
    var max: usize = 0;
    inline for (entity_names) |name| {
        const n = @typeInfo(@TypeOf(@field(entity_defs, name).fields)).@"struct".field_names.len;
        if (n > max) max = n;
    }
    return max;
}

const max_field_count = maxFieldCount();

var input_buf: [8192]u8 = undefined;
var json_buf: [8192]u8 = undefined;
var schema_buf: [32768]u8 = undefined;
var schema_len_value: usize = 0;
var schema_ready: bool = false;
var json_len_value: usize = 0;
var lengths_buf: [max_field_count]usize = undefined;

fn schemaBytes() []const u8 {
    if (!schema_ready) {
        const s = zigma_json.stringifyEntityCatalog(type_defs, entity_defs, &schema_buf) catch unreachable;
        schema_len_value = s.len;
        schema_ready = true;
    }
    return schema_buf[0..schema_len_value];
}

export fn schema_ptr() [*]const u8 {
    return schemaBytes().ptr;
}

export fn schema_len() usize {
    return schemaBytes().len;
}

export fn input_ptr() [*]u8 {
    return &input_buf;
}

export fn input_len() usize {
    return input_buf.len;
}

export fn lengths_ptr() [*]usize {
    return &lengths_buf;
}

export fn json_ptr() [*]const u8 {
    return &json_buf;
}

export fn json_len() usize {
    return json_len_value;
}

/// Year, month, day in struct field order from `YYYY-MM-DD`.
fn parseDateStruct(comptime T: type, s: []const u8) T {
    const names = @typeInfo(T).@"struct".field_names;
    var result: T = undefined;
    if (s.len >= 10) {
        @field(result, names[0]) = std.fmt.parseInt(@FieldType(T, names[0]), s[0..4], 10) catch 0;
        @field(result, names[1]) = std.fmt.parseInt(@FieldType(T, names[1]), s[5..7], 10) catch 0;
        @field(result, names[2]) = std.fmt.parseInt(@FieldType(T, names[2]), s[8..10], 10) catch 0;
    } else {
        inline for (names) |name| {
            @field(result, name) = 0;
        }
    }
    return result;
}

fn parseField(comptime FieldType: type, bytes: []const u8) FieldType {
    switch (@typeInfo(FieldType)) {
        .pointer => |p| {
            if (p.size == .slice and p.child == u8) return bytes;
            @compileError("unsupported field type " ++ @typeName(FieldType));
        },
        .int => return std.fmt.parseInt(FieldType, bytes, 10) catch 0,
        .bool => return std.mem.eql(u8, bytes, "true") or std.mem.eql(u8, bytes, "1"),
        .@"struct" => {
            if (comptime zigma_json.isDateStruct(FieldType)) return parseDateStruct(FieldType, bytes);
            @compileError("unsupported field type " ++ @typeName(FieldType));
        },
        else => @compileError("unsupported field type " ++ @typeName(FieldType)),
    }
}

fn buildRowJson(comptime entity: anytype) usize {
    const Row = zigma.RecordInstanceType(type_defs, entity.fields);
    var row: Row = undefined;
    var offset: usize = 0;
    inline for (@typeInfo(Row).@"struct".field_names, 0..) |name, i| {
        const len = lengths_buf[i];
        if (offset + len > input_buf.len) return 0;
        @field(row, name) = parseField(@FieldType(Row, name), input_buf[offset..][0..len]);
        offset += len;
    }
    const json_slice = zigma_json.stringifyRecord(row, &json_buf) catch return 0;
    json_len_value = json_slice.len;
    return json_slice.len;
}

/// Packed strings in `input_buf`; per-field lengths in `lengths_buf`.
/// Returns the JSON length written to `json_buf`, or 0 on error.
export fn build_row(entity_index: u32) usize {
    @setEvalBranchQuota(10000);
    inline for (entity_names, 0..) |name, i| {
        if (entity_index == i) return buildRowJson(@field(entity_defs, name));
    }
    return 0;
}

export fn create_row(entity_index: u32) void {
    const len = build_row(entity_index);
    if (len == 0) return;
    js_send_post(json_buf[0..len].ptr, len);
}
