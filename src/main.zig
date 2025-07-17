const std = @import("std");
const builtin = @import("builtin");

const Posts = @import("Posts.zig");
const ZtmlParser = @import("ztml/Parser.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    // var posts = try Posts.init(gpa, "site/posts/");
    // defer posts.deinit(gpa);
    //
    // for (posts.list.items) |*p| {
    //     p.debug();
    // }
    const x = try ZtmlParser.parse(gpa, "<body>hello {{ v title }} thank you!</body>");
    std.debug.print("{s}\n", .{x});
    defer gpa.free(x);
}

test {
    @import("std").testing.refAllDecls(@This());
}
