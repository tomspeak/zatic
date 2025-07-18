const std = @import("std");

// find `{{`, and extract whats between `}}` like we do for front matter
// parse what the context is, either
//      {{ fn param }}
//      {{ fn }}
//  include "path"
//  slot "name"
//  css
//  js

const FnKind = enum {
    v,
    css,
    js,
    slot,
    include,
};

pub const Value = union(enum) {
    string: []const u8,
    bool: bool,
    number: f64,
    array: []Value,
    object: std.StringHashMap(Value),

    pub fn toString(self: *Value, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self.*) {
            .string => |s| try allocator.dupe(u8, s),
            else => @panic("unsupported toString"),
        };
    }
};

// TODO: potentially made more efficient by continually looping doing indexOf("{{")
pub fn parse(allocator: std.mem.Allocator, buf: []const u8, ctx: *const std.StringHashMap(Value)) ![]u8 {
    var output = std.ArrayListUnmanaged(u8).empty;
    var index: usize = 0;
    var cursor: usize = 0;
    std.debug.print("ctx: {any}\n", .{ctx.get("title")});

    while (index < buf.len) {
        if (index + 2 > buf.len) {
            // We're at the end, no more {{ can be beyond this point
            // This will be the default case if a file with no {{ }} is passed.
            try output.appendSlice(allocator, buf[cursor..buf.len]);
            break;
        }

        // Whatever this is, its just normal HTML and not trying to call a template func
        if (!std.mem.eql(u8, buf[index .. index + 2], "{{")) {
            index += 1;
            continue;
        }

        // We match on {{, which means we want to store everything we've seen up until this point
        try output.appendSlice(allocator, buf[cursor..index]);

        // We jump forward to get over the {{ as its no longer relevant
        index += 2;

        // Find the boundary index for the closing }}
        const end_index = std.mem.indexOfPos(u8, buf, cursor, "}}") orelse @panic("no closing }} ");

        // Pass in the content between {{ }}, convert it into "html" and append
        const transformedContent = try handle(allocator, buf[index..end_index], ctx);
        defer allocator.free(transformedContent);
        try output.appendSlice(allocator, transformedContent);

        // Our new starting point is the end index + 2, which puts us right after the closing }}
        index = end_index + 2;
        // Set our cursor to save this position as the next time we find a {{ we are going to
        // start appending from this saved index.
        cursor = index;

        index += 1;
    }

    return try output.toOwnedSlice(allocator);
}

pub fn handle(allocator: std.mem.Allocator, buf: []const u8, ctx: *const std.StringHashMap(Value)) ![]const u8 {
    var split = std.mem.splitScalar(u8, std.mem.trim(u8, buf, " "), ' ');

    const func = split.next() orelse @panic("no func passed to {{ }}");
    const funcEnum = std.meta.stringToEnum(FnKind, func) orelse @panic("unrecognized funcEnum, could not convert to FnKind");

    switch (funcEnum) {
        .v => {
            const param = split.next() orelse @panic("v func was passed with no param");
            var ctxValue = ctx.get(param);
            const ctxStr = try ctxValue.?.toString(allocator);
            return ctxStr;
        },
        .css => {
            const prefix = "<style>";
            const suffix = "</style>";

            const css_path = "site/assets/main.css";
            const file = try std.fs.cwd().openFile(css_path, .{});
            defer file.close();

            const stat = try file.stat();
            const css_len: usize = @intCast(stat.size);

            const total_len = prefix.len + css_len + suffix.len;
            const result = try allocator.alloc(u8, total_len);

            var stream = std.io.fixedBufferStream(result);
            const writer = stream.writer();

            try writer.writeAll(prefix);

            var buffer: [512]u8 = undefined;
            var reader = file.reader();
            while (true) {
                const n = try reader.read(&buffer);
                if (n == 0) break; // EOF
                try writer.writeAll(buffer[0..n]);
            }

            try writer.writeAll(suffix);

            return result;
        },
        else => {
            @panic("unsupported funcEnum, even though it is a real and valid FnKind enum");
        },
    }

    std.debug.print("handle: {s}\n", .{buf});
}
