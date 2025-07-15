const std = @import("std");
const builtin = @import("builtin");

const Post = @import("post/index.zig");

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

    const posts = Post.init(gpa, "site/posts/") catch |e| {
        std.debug.print("err_type: {}\n", .{e});
        std.process.exit(1);
    };
    defer {
        for (posts) |*p| {
            p.deinit(gpa);
        }
        gpa.free(posts);
    }

    for (posts) |*p| {
        p.debug();
    }
}

test {
    @import("std").testing.refAllDecls(@This());
}
