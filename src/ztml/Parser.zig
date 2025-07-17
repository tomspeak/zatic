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

pub fn parse(allocator: std.mem.Allocator, buf: []const u8) ![]u8 {
    var output = std.ArrayListUnmanaged(u8).empty;
    var index: usize = 0;
    var cursor: usize = 0;

    while (index < buf.len) {
        if (index + 2 > buf.len) {
            try output.appendSlice(allocator, buf[cursor..buf.len]);
            break;
        }
        if (!std.mem.eql(u8, buf[index .. index + 2], "{{")) {
            index += 1;
            continue;
        }

        try output.appendSlice(allocator, buf[cursor..index]);

        // indexOf the ending }}, take index..end{{ slice, send to handle()
        const end_index = std.mem.indexOfPos(u8, buf, cursor, "}}") orelse @panic("no closing }} ");
        index = end_index + 2; // account for "}}"
        cursor = index;

        handle(allocator, buf[cursor..index]);
        // push handle() result to output
        // continue
        index += 1;
    }
    // 2. support include "path"
    //

    return try output.toOwnedSlice(allocator);
}

pub fn handle(allocator: std.mem.Allocator, buf: []const u8) void {
    // split on scalar ' '
    // convert first param to FnKind enum
    // check for optional second param
    _ = allocator;
    std.debug.print("handle: {s}\n", .{buf});
}
