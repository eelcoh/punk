//! Format a punk buffer with the import context of its path on disk.

const std = @import("std");
const punk = @import("mod.zig");

const source_limit: std.Io.Limit = .limited(256 * 1024 * 1024);

pub fn main(init: std.process.Init) void {
    run(init) catch |err| {
        std.debug.print("punk fmt: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn run(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    // The launcher leaves the command name in the arguments.
    if (args.len != 5 or !std.mem.eql(u8, args[1], "fmt")) usage();
    const path = if (std.mem.eql(u8, args[2], "--stdin") and std.mem.eql(u8, args[3], "--path"))
        args[4]
    else if (std.mem.eql(u8, args[2], "--path") and std.mem.eql(u8, args[4], "--stdin"))
        args[3]
    else
        usage();
    if (!punk.isPunkPath(path)) usage();

    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().readerStreaming(init.io, &input_buffer);
    const source = try input.interface.allocRemaining(arena, source_limit);

    var io = init.io;
    const resolver = try punk.resolverFor(arena, path, .{ .ctx = &io, .read = readFile });
    var diag: punk.Diagnostic = .{};
    const output = punk.format.formatWith(arena, source, &diag, resolver) catch |err| switch (err) {
        error.OutOfMemory => return err,
        error.ParseError, error.Unsafe => {
            std.debug.print("{s}:{d}:{d}: {s}\n", .{ path, diag.line, diag.col, diag.message });
            std.process.exit(1);
        },
    };
    var output_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &output_buffer);
    try stdout.interface.writeAll(output);
    try stdout.interface.flush();
}

fn readFile(ctx: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8) ?[]u8 {
    const io: *const std.Io = @ptrCast(@alignCast(ctx.?));
    return std.Io.Dir.cwd().readFileAlloc(io.*, path, allocator, source_limit) catch null;
}

fn usage() noreturn {
    std.debug.print("usage: punk fmt --stdin --path FILE.punk\n", .{});
    std.process.exit(2);
}
