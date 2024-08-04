const std = @import("std");

fn get_cwd(path: std.fs.Dir) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const path_str = try path.realpathAlloc(alloc, ".");

    return try std.heap.page_allocator.dupe(u8, path_str);
}

fn compareStrings(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs).compare(std.math.CompareOperator.lt);
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const path = if (std.os.argv.len >= 2)
        std.fs.openDirAbsolute(std.mem.span(std.os.argv[1]), .{}) catch |err| {
            try stdout.print("failed opening directory {any}\n", .{err});
            return;
        }
    else
        std.fs.cwd();

    const cwd = get_cwd(path) catch |err| {
        try stdout.print("failed getting directory path: {any}\n", .{err});
        return;
    };

    try stdout.print("path: {s}\n", .{cwd});
    std.heap.page_allocator.free(cwd);

    var dir = path.openDir(".", .{ .iterate = true }) catch |err| {
        try stdout.print("failed opening iterating directory: {any}", .{err});
        return;
    };
    defer dir.close();

    var it = dir.iterate();
    var entries = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer entries.deinit();

    while (try it.next()) |dirContent| {
        if (dirContent.name[0] == '.') {
            continue;
        }

        try entries.append(try std.heap.page_allocator.dupe(u8, dirContent.name));
    }

    const entriesList = try entries.toOwnedSlice();
    std.mem.sort([]const u8, entriesList, {}, compareStrings);

    for (entriesList) |entry| {
        // try stdout.print("=> {s}\n", .{entry});

        const metadata = path.statFile(entry) catch {
            try stdout.print("failed statfile({s})\n", .{entry});
            continue;
        };

        const mode = metadata.mode % 0o1000;

        const c: u8 = switch (metadata.kind) {
            std.fs.File.Kind.block_device => 'b',
            std.fs.File.Kind.character_device => 'c',
            std.fs.File.Kind.directory => 'd',
            std.fs.File.Kind.file => 'f',
            std.fs.File.Kind.sym_link => 's',
            std.fs.File.Kind.named_pipe => '!',
            else => '?',
        };

        try stdout.print("{c} {o} {d:9} {s}\n", .{ c, mode, metadata.size, entry });

        std.heap.page_allocator.free(entry);
    }
}
