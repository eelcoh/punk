//! Platform names: `app [main!] { Platform: platform "cli" }`.
//!
//! A platform given by a name (lowercase letters, digits and `-`, nothing
//! else) is one of the platforms that come with punk: `cli`, `server`,
//! `tui`. Roc only takes a path or a URL here, and no absolute path, so the
//! name becomes the relative path from the app's folder to that platform's
//! `main.roc` next to the compiler (see `src/punk/roc/vfs.zig`, which knows
//! where that is). A path (`"../platforms/cli/main.roc"`) or URL stays as it
//! is.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Gives the spec to write for the platform `name` of the app at
/// `app_path`: the relative path to its `main.roc`. Null when punk has no
/// platform of that name.
pub const Finder = struct {
    ctx: ?*anyopaque,
    find: *const fn (ctx: ?*anyopaque, arena: Allocator, app_path: []const u8, name: []const u8) ?[]const u8,
};

pub const Found = struct {
    /// The source with the name replaced, or the source itself.
    src: []const u8,
    /// Set when the header names a platform punk does not have.
    unknown: ?struct { name: []const u8, line: u32, col: u32 } = null,
};

/// Whether `spec` is a platform name rather than a path or URL.
pub fn isName(spec: []const u8) bool {
    if (spec.len == 0 or !std.ascii.isLower(spec[0])) return false;
    for (spec) |c| if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '-')) return false;
    return true;
}

/// The place of the platform's string in the header of an app, as
/// [start, end) of the text between the quotes. Null when `src` is not an
/// app or names no platform.
pub fn specRange(src: []const u8) ?[2]usize {
    // The header is the first thing that is not a comment or blank line,
    // and goes on as long as lines are indented.
    var i: usize = 0;
    while (i < src.len) {
        const line_end = std.mem.indexOfScalarPos(u8, src, i, '\n') orelse src.len;
        const line = std.mem.trim(u8, src[i..line_end], " \t\r");
        if (line.len == 0 or std.mem.startsWith(u8, line, "--")) {
            i = line_end + 1;
            continue;
        }
        break;
    }
    if (!std.mem.startsWith(u8, src[i..], "app") or (i + 3 < src.len and isIdent(src[i + 3]))) return null;
    var end = i;
    while (end < src.len) {
        const nl = std.mem.indexOfScalarPos(u8, src, end, '\n') orelse src.len;
        end = nl;
        if (nl + 1 >= src.len or !(src[nl + 1] == ' ' or src[nl + 1] == '\t')) break;
        end = nl + 1;
    }
    const header = src[i..end];
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, header, at, "platform")) |p| {
        at = p + "platform".len;
        if (p > 0 and isIdent(header[p - 1])) continue;
        var q = at;
        while (q < header.len and (header[q] == ' ' or header[q] == '\t' or header[q] == '\n' or header[q] == '\r')) q += 1;
        if (q == at or q >= header.len or header[q] != '"') continue;
        const close = std.mem.indexOfScalarPos(u8, header, q + 1, '"') orelse return null;
        return .{ i + q + 1, i + close };
    }
    return null;
}

fn isIdent(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// Replaces a platform name in the header of `src` by what `finder` gives.
pub fn resolve(arena: Allocator, src: []const u8, app_path: []const u8, finder: ?Finder) Allocator.Error!Found {
    const range = specRange(src) orelse return .{ .src = src };
    const name = src[range[0]..range[1]];
    if (!isName(name)) return .{ .src = src };
    const f = finder orelse return .{ .src = src };
    const spec = f.find(f.ctx, arena, app_path, name) orelse {
        var line: u32 = 1;
        var col: u32 = 1;
        for (src[0..range[0]]) |c| {
            if (c == '\n') {
                line += 1;
                col = 1;
            } else col += 1;
        }
        return .{ .src = src, .unknown = .{ .name = name, .line = line, .col = col - 1 } };
    };
    return .{ .src = try std.mem.concat(arena, u8, &.{ src[0..range[0]], spec, src[range[1]..] }) };
}

/// The relative path from the folder of `app_path` to `platforms_dir/name/main.roc`,
/// both made absolute against `cwd`, with `/` as separator.
pub fn relativeSpec(arena: Allocator, cwd: []const u8, app_path: []const u8, platforms_dir: []const u8, name: []const u8) Allocator.Error![]const u8 {
    const app_dir = std.fs.path.dirname(app_path) orelse ".";
    const from = try std.fs.path.resolve(arena, &.{ cwd, app_dir });
    const to = try std.fs.path.resolve(arena, &.{ cwd, platforms_dir, name, "main.roc" });
    const rel = try std.fs.path.relativeAllocPosix(arena, "/", from, to);
    return rel;
}

test "platform names" {
    try std.testing.expect(isName("cli"));
    try std.testing.expect(isName("server"));
    try std.testing.expect(isName("my-tui2"));
    try std.testing.expect(!isName("../platforms/cli/main.roc"));
    try std.testing.expect(!isName("https://example.com/p.tar.zst"));
    try std.testing.expect(!isName("Cli"));
    try std.testing.expect(!isName(""));
}

fn fakeFind(_: ?*anyopaque, arena: Allocator, app_path: []const u8, name: []const u8) ?[]const u8 {
    if (!std.mem.eql(u8, name, "cli") and !std.mem.eql(u8, name, "server")) return null;
    return relativeSpec(arena, "/home/me", app_path, "/home/me/.punk/current/platforms", name) catch null;
}

test "a platform name becomes the path to the installed platform" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const finder: Finder = .{ .ctx = null, .find = fakeFind };

    const found = try resolve(a,
        \\-- an app
        \\app [main!] { Platform: platform "cli" }
        \\
        \\import Platform.Stdout
        \\
    , "code/hello/Main.punk", finder);
    try std.testing.expectEqualStrings(
        \\-- an app
        \\app [main!] { Platform: platform "../../.punk/current/platforms/cli/main.roc" }
        \\
        \\import Platform.Stdout
        \\
    , found.src);
    try std.testing.expect(found.unknown == null);

    // Over more lines, next to a package.
    const multi = try resolve(a,
        \\app [handle!] {
        \\    Platform: platform "server",
        \\    Json: "../packages/json/main.roc",
        \\}
        \\
        \\x = "platform \"cli\""
    , "/srv/app/Shortener.punk", finder);
    try std.testing.expect(std.mem.indexOf(u8, multi.src, "platform \"../../home/me/.punk/current/platforms/server/main.roc\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, multi.src, "x = \"platform \\\"cli\\\"\"") != null);
}

test "paths, URLs and modules stay as they are" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const finder: Finder = .{ .ctx = null, .find = fakeFind };
    const sources = [_][]const u8{
        "app [main!] { Platform: platform \"../platforms/cli/main.roc\" }\n",
        "app [main!] { Platform: platform \"https://example.com/cli.tar.zst\" }\n",
        "module [area]\n\narea = fn x -> x\n",
        "x = 1\n",
    };
    for (sources) |src| {
        const found = try resolve(a, src, "Main.punk", finder);
        try std.testing.expectEqualStrings(src, found.src);
        try std.testing.expect(found.unknown == null);
    }
    // Without a finder (punk2roc, the formatter) a name stays too.
    const plain = "app [main!] { Platform: platform \"cli\" }\n";
    try std.testing.expectEqualStrings(plain, (try resolve(a, plain, "Main.punk", null)).src);
}

test "an unknown platform name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const finder: Finder = .{ .ctx = null, .find = fakeFind };
    const found = try resolve(arena.allocator(), "\napp [main!] { Platform: platform \"web\" }\n", "Main.punk", finder);
    try std.testing.expectEqualStrings("web", found.unknown.?.name);
    try std.testing.expectEqual(@as(u32, 2), found.unknown.?.line);
    try std.testing.expectEqual(@as(u32, 34), found.unknown.?.col);
}
