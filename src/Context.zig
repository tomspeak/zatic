const std = @import("std");
const ZtmlParser = @import("ztml/Parser.zig");
const config = @import("config.zig");

pub const GlobalCtx = struct {
    site_title: []const u8,
    base_url: []const u8,

    pub const instance: GlobalCtx = .{
        .site_title = config.site_title,
        .base_url = config.base_url,
    };
};

fn addFieldToContext(context: *std.StringHashMap(ZtmlParser.Value), field_name: []const u8, field_type: type, field_value: anytype) !void {
    switch (field_type) {
        []const u8 => {
            try context.put(field_name, ZtmlParser.Value{ .string = field_value });
        },
        ?[]const u8, ?[]u8 => {
            if (field_value) |val| {
                try context.put(field_name, ZtmlParser.Value{ .string = val });
            }
        },
        bool => {
            try context.put(field_name, ZtmlParser.Value{ .bool = field_value });
        },
        else => {},
    }
}

pub fn structToContext(allocator: std.mem.Allocator, comptime T: type, data: *const T) !std.StringHashMap(ZtmlParser.Value) {
    var context = std.StringHashMap(ZtmlParser.Value).init(allocator);

    inline for (std.meta.fields(T)) |field| {
        const field_value = @field(data, field.name);
        try addFieldToContext(&context, field.name, field.type, field_value);

        // Handle nested structs by flattening their fields
        if (@typeInfo(field.type) == .@"struct") {
            inline for (std.meta.fields(field.type)) |nested_field| {
                const nested_value = @field(field_value, nested_field.name);
                try addFieldToContext(&context, nested_field.name, nested_field.type, nested_value);
            }
        }
    }

    return context;
}

pub fn mergeContexts(allocator: std.mem.Allocator, contexts: []const std.StringHashMap(ZtmlParser.Value)) !std.StringHashMap(ZtmlParser.Value) {
    var merged = std.StringHashMap(ZtmlParser.Value).init(allocator);

    for (contexts) |ctx| {
        var iter = ctx.iterator();
        while (iter.next()) |entry| {
            try merged.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    return merged;
}

