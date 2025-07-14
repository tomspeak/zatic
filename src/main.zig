const std = @import("std");
const builtin = @import("builtin");

const Post = @import("post/index.zig");

pub const std_options: std.Options = .{
    .log_level = .info,
};

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    // TODO: see if I can fit the entire thing on the stack.
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var post = try Post.init(gpa, "site/posts/test.md");
    defer post.deinit(gpa);
    post.debug();
}

test {
    @import("std").testing.refAllDecls(@This());
}
