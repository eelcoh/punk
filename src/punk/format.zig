//! `punk fmt`: the canonical layout of punkroc source, with no options (like
//! elm-format). Agents do not have to think about style, and a reader always
//! sees the same shape.
//!
//! The formatter works on the tokens, not on a syntax tree, so it never loses
//! a comment and never changes what the code means:
//!
//! - indentation is 4 spaces per level (each deeper indentation in the
//!   source becomes one level deeper than the line it belongs under);
//! - one space between tokens, none inside `( )` and `[ ]`, one inside
//!   `{ }`, none before a comma and one after it, spaces around operators,
//!   `=`, `->`, `:` and `|`; `.field` and `-x` keep their tight form;
//! - at most one blank line in a row; exactly one between top-level
//!   items, and none between an annotation and its definition or between
//!   imports;
//! - no trailing spaces, and one newline at the end of the file.
//!
//! Line breaks are the author's, except that a line longer than
//! `max_width` is split, the way elm-format writes such code (see
//! `breakLongLines`): the body of a definition or `case` branch goes on the
//! next line, a pipeline gets one line per `|>`, an `if` gets its branches
//! on lines of their own, a list, record or tuple is written with leading
//! commas, a call gets one argument per line, and a lambda in parentheses
//! gets its body on a line of its own. A line that is still long (a long
//! string) stays. The formatter does not join lines.
//! Header lines (`app`, `module`, `import`) are kept as written.
//!
//! To be sure the layout changed nothing else, the formatted text is
//! translated again and its Roc translation compared with that of the
//! original (ignoring whitespace). If they differ, `format` refuses with
//! `error.Unsafe` and the file is left alone.

const std = @import("std");
const translate = @import("translate.zig");

const Allocator = std.mem.Allocator;
const Token = translate.Token;
const Tag = translate.Tag;
const Diagnostic = translate.Diagnostic;

pub const Error = error{ ParseError, OutOfMemory, Unsafe };

/// The indentation of one level.
pub const indent_width = 4;

/// Formats punkroc source. On a syntax error `error.ParseError` is returned
/// with `diag` filled in; the source is left as it is.
pub fn format(a: Allocator, src: []const u8, diag: *Diagnostic) Error![]const u8 {
    return formatWith(a, src, diag, null);
}

/// Like `format`, with the modules the file imports read through
/// `resolver`, so that the translations it compares see their tables.
pub fn formatWith(a: Allocator, src: []const u8, diag: *Diagnostic, resolver: ?translate.Resolver) Error![]const u8 {
    const before = try translate.translateWith(a, src, diag, resolver);
    const toks = try translate.lex(a, src, diag);
    const laid_out = try render(a, src, toks);
    const out = try breakLongLines(a, laid_out, before, resolver);
    var d2: Diagnostic = .{};
    const after = translate.translateWith(a, out, &d2, resolver) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ParseError => return unsafe(diag, d2.line, d2.col),
    };
    if (!sameIgnoringSpace(before, after)) return unsafe(diag, 1, 1);
    return out;
}

fn unsafe(diag: *Diagnostic, line: u32, col: u32) error{Unsafe} {
    diag.* = .{ .line = line, .col = col, .message = "punk fmt would change what this file means, so it left the file alone (this is a bug in punk fmt)" };
    return error.Unsafe;
}

/// Whether `x` and `y` are the same text when every run of whitespace counts
/// as one space.
pub fn sameIgnoringSpace(x: []const u8, y: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (true) {
        const ws_i = skipSpace(x, &i);
        const ws_j = skipSpace(y, &j);
        const end_i = i == x.len;
        const end_j = j == y.len;
        if (end_i or end_j) return end_i and end_j;
        if (ws_i != ws_j) return false;
        if (x[i] != y[j]) return false;
        i += 1;
        j += 1;
    }
}

fn skipSpace(s: []const u8, i: *usize) bool {
    const start = i.*;
    while (i.* < s.len and std.ascii.isWhitespace(s[i.*])) i.* += 1;
    return i.* > start;
}

const Level = struct { orig: u32, new: u32 };

const Renderer = struct {
    a: Allocator,
    src: []const u8,
    toks: []const Token,
    out: std.ArrayList(u8) = .empty,
    stack: std.ArrayList(Level) = .empty,
    /// Indentation of the current line, in the source and in the output.
    old_indent: u32 = 1,
    new_indent: u32 = 1,
    /// Whether the token written last was a prefix `-` or `!`.
    prev_unary: bool = false,
    /// For each `(` and `[`: whether its items are written with leading
    /// commas on lines of their own. Such a bracket gets a space after it,
    /// Elm style (`[ 1` / `, 2` / `]`).
    spans_lines: []bool = &.{},
    /// For each trailing `,` at the end of a line inside brackets: move it
    /// to a leading `, ` on the next line.
    move_comma: []bool = &.{},

    fn w(r: *Renderer, s: []const u8) Error!void {
        try r.out.appendSlice(r.a, s);
    }

    fn spaces(r: *Renderer, n: u32) Error!void {
        try r.out.appendNTimes(r.a, ' ', n);
    }

    fn trimTrailingSpaces(r: *Renderer) void {
        while (r.out.items.len > 0 and r.out.items[r.out.items.len - 1] == ' ') r.out.items.len -= 1;
    }

    /// The new column for a line that starts at column `col` in the source.
    fn indentFor(r: *Renderer, col: u32) Error!u32 {
        while (r.stack.items.len > 1 and r.stack.items[r.stack.items.len - 1].orig > col) r.stack.items.len -= 1;
        const top = r.stack.items[r.stack.items.len - 1];
        if (top.orig == col) return top.new;
        if (col < top.orig) return top.new; // only the column-1 level is left
        const new = top.new + indent_width;
        try r.stack.append(r.a, .{ .orig = col, .new = new });
        return new;
    }

    /// Writes `text`, which starts in the source at a column `delta` columns
    /// from where it is written now, moving its later lines by as much.
    fn writeShifted(r: *Renderer, text: []const u8, delta: i64) Error!void {
        var lines = std.mem.splitScalar(u8, text, '\n');
        var first = true;
        while (lines.next()) |l| {
            if (!first) {
                try r.w("\n");
                var line = l;
                if (delta > 0) {
                    if (line.len > 0) try r.spaces(@intCast(delta));
                } else if (delta < 0) {
                    var k: usize = 0;
                    while (k < @as(usize, @intCast(-delta)) and k < line.len and line[k] == ' ') k += 1;
                    line = line[k..];
                }
                try r.w(line);
            } else try r.w(l);
            first = false;
        }
    }

    fn markLeadingCommas(r: *Renderer) Error!void {
        r.spans_lines = try r.a.alloc(bool, r.toks.len);
        @memset(r.spans_lines, false);
        r.move_comma = try r.a.alloc(bool, r.toks.len);
        @memset(r.move_comma, false);
        const Open = struct { index: usize, is_lambda: bool };
        var open: std.ArrayList(Open) = .empty;
        var i: usize = 0;
        while (i < r.toks.len) {
            const t = r.toks[i];
            if (t.tag == .kw_header and t.first_on_line and t.col == 1) {
                while (i + 1 < r.toks.len and r.toks[i + 1].tag != .eof and !(r.toks[i + 1].first_on_line and r.toks[i + 1].col == 1)) i += 1;
                i += 1;
                continue;
            }
            switch (t.tag) {
                .lparen, .lbrack, .lbrace => try open.append(r.a, .{
                    .index = i,
                    .is_lambda = t.tag == .lparen and i + 1 < r.toks.len and r.toks[i + 1].tag == .kw_fn,
                }),
                .rparen, .rbrack, .rbrace => _ = open.pop(),
                .comma => if (open.items.len > 0) {
                    const top = open.items[open.items.len - 1];
                    if (t.first_on_line) {
                        r.spans_lines[top.index] = true;
                    } else if (!top.is_lambda and i + 1 < r.toks.len and r.toks[i + 1].first_on_line and !isClose(r.toks[i + 1].tag) and r.toks[i + 1].tag != .eof) {
                        r.move_comma[i] = true;
                        r.spans_lines[top.index] = true;
                    }
                },
                else => {},
            }
            i += 1;
        }
    }

    fn run(r: *Renderer) Error![]const u8 {
        try r.markLeadingCommas();
        try r.stack.append(r.a, .{ .orig = 1, .new = 1 });
        const Bracket = struct { tag: Tag, comma_col: ?u32 };
        var brackets: std.ArrayList(Bracket) = .empty;
        var pending_comma = false;
        var pending_col: ?u32 = null;
        var prev: ?Token = null;
        var prev_end: usize = 0;
        // The first token of the previous top-level item, and its second.
        var item_first: ?Token = null;
        var item_second: ?Token = null;
        var i: usize = 0;
        while (i < r.toks.len) {
            const t = r.toks[i];
            const gap = r.src[prev_end..t.start];
            if (t.tag == .eof) {
                try r.lineGap(gap, prev != null, false, 0, true);
                break;
            }
            if (t.tag == .comma and r.move_comma[i]) {
                const comment = std.mem.trim(u8, gap, " \r");
                if (comment.len > 0) {
                    try r.w(" ");
                    try r.w(comment);
                }
                pending_comma = true;
                pending_col = if (brackets.items.len > 0) brackets.items[brackets.items.len - 1].comma_col else null;
                prev_end = t.end;
                i += 1;
                continue;
            }
            var moved_comma = false;
            if (t.first_on_line) {
                const new_col = if (pending_comma) blk: {
                    if (pending_col) |col| {
                        while (r.stack.items.len > 1 and r.stack.items[r.stack.items.len - 1].new > col) r.stack.items.len -= 1;
                        break :blk col;
                    }
                    break :blk try r.indentFor(t.col);
                } else try r.indentFor(t.col);
                var tight = false;
                if (t.col == 1) {
                    if (item_first) |f| tight = tightAfter(f, item_second, t, if (i + 1 < r.toks.len) r.toks[i + 1] else t);
                    item_first = t;
                    item_second = if (i + 1 < r.toks.len) r.toks[i + 1] else null;
                }
                try r.lineGap(gap, prev != null, t.col == 1 and prev != null, new_col, tight);
                r.old_indent = t.col;
                r.new_indent = new_col;
                try r.spaces(new_col - 1);
                if (pending_comma) {
                    try r.w(", ");
                    pending_comma = false;
                    pending_col = null;
                    moved_comma = true;
                }
                r.prev_unary = false;
                if (t.tag == .bar and !moved_comma and brackets.items.len > 0 and brackets.items[brackets.items.len - 1].tag == .lbrace) {
                    brackets.items[brackets.items.len - 1].comma_col = new_col;
                }
            } else {
                try r.inlineGap(gap, prev.?, t, i);
            }
            // A header is kept as written, up to the next top-level line.
            if (t.tag == .kw_header and t.first_on_line and t.col == 1) {
                var j = i;
                while (j + 1 < r.toks.len and r.toks[j + 1].tag != .eof and !(r.toks[j + 1].first_on_line and r.toks[j + 1].col == 1)) j += 1;
                var lines = std.mem.splitScalar(u8, r.src[t.start..r.toks[j].end], '\n');
                var first = true;
                while (lines.next()) |l| {
                    if (!first) try r.w("\n");
                    first = false;
                    try r.w(std.mem.trimEnd(u8, l, " \r"));
                }
                prev = r.toks[j];
                prev_end = r.toks[j].end;
                i = j + 1;
                continue;
            }
            if (isOpen(t.tag)) {
                try brackets.append(r.a, .{ .tag = t.tag, .comma_col = if (t.first_on_line and !moved_comma) r.new_indent else null });
            } else if (isClose(t.tag)) {
                _ = brackets.pop();
            }
            const delta: i64 = @as(i64, r.new_indent) - @as(i64, r.old_indent);
            try r.writeShifted(r.src[t.start..t.end], delta);
            r.prev_unary = isUnary(prev, t, r.toks, i);
            prev = t;
            prev_end = t.end;
            i += 1;
        }
        r.trimTrailingSpaces();
        while (r.out.items.len > 0 and r.out.items[r.out.items.len - 1] == '\n') r.out.items.len -= 1;
        try r.w("\n");
        return r.out.items;
    }

    /// Writes the space between two tokens on one line.
    fn inlineGap(r: *Renderer, gap: []const u8, prev: Token, cur: Token, i: usize) Error!void {
        // A block comment between them stays.
        const comment = std.mem.trim(u8, gap, " \r");
        if (comment.len > 0) {
            try r.w(" ");
            try r.w(comment);
            try r.w(" ");
            return;
        }
        const after_open = (prev.tag == .lparen or prev.tag == .lbrack) and r.spans_lines[i - 1];
        if (after_open or wantSpace(prev, cur, gap.len > 0, r.prev_unary, r.toks, i)) try r.w(" ");
    }

    /// Writes the line break(s) and comments between two lines. `at_top` is
    /// set when the next line is a new top-level item; `tight` when it may
    /// follow the item before it without a blank line.
    fn lineGap(r: *Renderer, gap: []const u8, after_token: bool, at_top: bool, new_col: u32, tight: bool) Error!void {
        var k: usize = 0;
        var newlines: u32 = 0;
        var entries: u32 = 0;
        const indent_out: u32 = if (new_col == 0) 1 else new_col;
        while (k < gap.len) {
            const c = gap[k];
            if (c == '\n') {
                newlines += 1;
                k += 1;
            } else if (c == ' ' or c == '\r') {
                k += 1;
            } else {
                // A comment.
                const comment_start = k;
                var end = k;
                if (c == '-') {
                    while (end < gap.len and gap[end] != '\n') end += 1;
                } else {
                    var depth: u32 = 0;
                    while (end < gap.len) {
                        if (end + 1 < gap.len and gap[end] == '{' and gap[end + 1] == '-') {
                            depth += 1;
                            end += 2;
                        } else if (end + 1 < gap.len and gap[end] == '-' and gap[end + 1] == '}') {
                            depth -= 1;
                            end += 2;
                            if (depth == 0) break;
                        } else end += 1;
                    }
                }
                const text = std.mem.trimEnd(u8, gap[comment_start..end], " \r");
                const line_start = if (std.mem.findScalarLast(u8, gap[0..comment_start], '\n')) |nl| nl + 1 else 0;
                const old_col: i64 = @intCast(comment_start - line_start + 1);
                if (newlines == 0 and after_token) {
                    // A comment at the end of the line before.
                    try r.w(" ");
                    try r.writeShifted(text, @as(i64, r.new_indent) - @as(i64, r.old_indent));
                } else {
                    try r.breaks(newlines, after_token or r.out.items.len > 0, at_top and entries == 0, tight);
                    try r.spaces(indent_out - 1);
                    try r.writeShifted(text, @as(i64, indent_out) - old_col);
                    entries += 1;
                }
                newlines = 0;
                k = end;
            }
        }
        if (new_col == 0) return; // end of file
        try r.breaks(newlines, after_token or r.out.items.len > 0, at_top and entries == 0, tight);
    }

    /// Ends the current line and writes the blank line (at most one) that
    /// should follow.
    fn breaks(r: *Renderer, newlines: u32, started: bool, at_top: bool, tight: bool) Error!void {
        r.trimTrailingSpaces();
        if (!started) return;
        try r.w("\n");
        const blank = if (at_top) !tight else newlines >= 2;
        if (blank) try r.w("\n");
    }
};

/// Whether a top-level item may follow the one before it without a blank
/// line: a definition after its annotation, an import after an import.
fn tightAfter(prev_first: Token, prev_second: ?Token, cur: Token, cur_second: Token) bool {
    if (isImport(prev_first) and isImport(cur)) return true;
    if (prev_first.tag == .lower and cur.tag == .lower and std.mem.eql(u8, prev_first.text, cur.text)) {
        const s = prev_second orelse return false;
        return s.tag == .colon and cur_second.tag != .colon;
    }
    return false;
}

fn isImport(t: Token) bool {
    return t.tag == .kw_header and std.mem.eql(u8, t.text, "import");
}

fn endsValue(tag: Tag) bool {
    return switch (tag) {
        .lower, .upper, .qlower, .int, .float, .string, .char, .rparen, .rbrack, .rbrace, .dot_field, .underscore => true,
        else => false,
    };
}

fn isOp(t: Token, text: []const u8) bool {
    return t.tag == .op and std.mem.eql(u8, t.text, text);
}

/// Whether `cur` (at index `i`) is a prefix `-` or `!`: written tight
/// against what follows, and not after a value without a space.
fn isUnary(prev: ?Token, cur: Token, toks: []const Token, i: usize) bool {
    if (!(isOp(cur, "-") or isOp(cur, "!"))) return false;
    const next = if (i + 1 < toks.len) toks[i + 1] else return false;
    if (next.space_before or next.first_on_line) return false;
    const p = prev orelse return true;
    if (cur.first_on_line) return true;
    return !endsValue(p.tag) or cur.space_before;
}

fn isRangeOp(t: Token) bool {
    return isOp(t, "..=") or isOp(t, "..<");
}

fn spacedPunct(tag: Tag) bool {
    return switch (tag) {
        .equals, .arrow, .fat_arrow, .colon, .bar => true,
        else => false,
    };
}

/// Whether there is a space between `prev` and `cur` (at index `i`) on one
/// line; `had` tells whether the source had one.
fn wantSpace(prev: Token, cur: Token, had: bool, prev_unary: bool, toks: []const Token, i: usize) bool {
    if (cur.tag == .dot_field) return had; // `.name` access vs accessor function
    if (cur.tag == .comma) return false;
    if (prev.tag == .comma) return true;
    if (prev.tag == .lparen or prev.tag == .lbrack) return false;
    if (cur.tag == .rparen or cur.tag == .rbrack) return false;
    if (prev.tag == .lbrace) return cur.tag != .rbrace;
    if (cur.tag == .rbrace) return prev.tag != .lbrace;
    if (prev.tag == .double_dot) return false;
    if (cur.tag == .double_dot) return had;
    if (prev_unary) return false;
    if (cur.tag == .op) {
        if (isRangeOp(cur)) return had;
        if (isUnary(prev, cur, toks, i)) return had or !endsValue(prev.tag) and prev.tag != .lparen;
        return true;
    }
    if (prev.tag == .op) return if (isRangeOp(prev)) had else true;
    if (spacedPunct(cur.tag) or spacedPunct(prev.tag)) return true;
    return had;
}

/// Lays out `toks` (the tokens of `src`) without the safety check.
pub fn render(a: Allocator, src: []const u8, toks: []const Token) Error![]const u8 {
    var r = Renderer{ .a = a, .src = src, .toks = toks };
    return r.run();
}

// Long lines ----------------------------------------------------------------

/// The longest line `punk fmt` leaves alone, in characters.
pub const max_width = 80;

/// Splits the lines of `text` (already laid out by `render`) that are longer
/// than `max_width`, one step at a time, until none can be split further.
/// Each step is kept only when the file still means the same (its Roc
/// translation is `roc`), so a split the layout rules don't allow is simply
/// not made.
fn breakLongLines(a: Allocator, text: []const u8, roc: []const u8, resolver: ?translate.Resolver) Error![]const u8 {
    var cur = text;
    var from_line: u32 = 1;
    var steps: usize = 0;
    outer: while (steps < 10_000) : (steps += 1) {
        var diag: Diagnostic = .{};
        const toks = translate.lex(a, cur, &diag) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ParseError => return cur,
        };
        var i: usize = 0;
        while (i < toks.len and toks[i].tag != .eof) {
            // The tokens of one line.
            const line = toks[i].line;
            var j = i;
            while (j < toks.len and toks[j].tag != .eof and toks[j].line == line) j += 1;
            defer i = j;
            if (line < from_line) continue;
            const start = lineStart(cur, toks[i].start);
            const end = lineEnd(cur, toks[i].start);
            if (width(cur[start..end]) <= max_width) continue;
            // Long only because of its strings: splitting would not help.
            if (width(cur[start..end]) - stringWidth(cur, toks[i..j]) <= max_width) continue;
            // A token that goes on past this line (a multi-line string).
            if (toks[j - 1].end > end) continue;
            if (toks[i].tag == .kw_header) continue;
            const replacement = (try splitLine(a, cur, toks[i..j], end)) orelse continue;
            const candidate = try std.mem.concat(a, u8, &.{ cur[0..start], replacement, cur[end..] });
            const relaid = relayout(a, candidate) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => continue,
            };
            var d2: Diagnostic = .{};
            const after = translate.translateWith(a, relaid, &d2, resolver) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.ParseError => continue,
            };
            if (!sameIgnoringSpace(roc, after)) continue;
            cur = relaid;
            from_line = line;
            continue :outer;
        }
        return cur;
    }
    return cur;
}

fn relayout(a: Allocator, text: []const u8) Error![]const u8 {
    var diag: Diagnostic = .{};
    const toks = try translate.lex(a, text, &diag);
    return render(a, text, toks);
}

fn lineStart(text: []const u8, at: usize) usize {
    return if (std.mem.findScalarLast(u8, text[0..at], '\n')) |nl| nl + 1 else 0;
}

fn lineEnd(text: []const u8, at: usize) usize {
    return std.mem.findScalarPos(u8, text, at, '\n') orelse text.len;
}

/// How much wider than `""` the long string literals among `toks` are (a
/// short one is like any other token).
fn stringWidth(text: []const u8, toks: []const Token) usize {
    var n: usize = 0;
    for (toks) |t| if (t.tag == .string) {
        const w = width(text[t.start..t.end]);
        if (w > 20) n += w - 2;
    };
    return n;
}

fn width(line: []const u8) usize {
    return std.unicode.utf8CountCodepoints(line) catch line.len;
}

fn isOpen(tag: Tag) bool {
    return tag == .lparen or tag == .lbrack or tag == .lbrace;
}

fn isClose(tag: Tag) bool {
    return tag == .rparen or tag == .rbrack or tag == .rbrace;
}

/// The index of the token that closes the bracket at `open`, or null when it
/// is not among `toks`.
fn closing(toks: []const Token, open: usize) ?usize {
    var depth: usize = 0;
    for (toks[open..], open..) |t, k| {
        if (isOpen(t.tag)) depth += 1;
        if (isClose(t.tag)) {
            depth -= 1;
            if (depth == 0) return k;
        }
    }
    return null;
}

/// The tokens of `toks[from..]` at bracket depth 0 (relative to `from`)
/// that satisfy `pred`. Null when a bracket closes that opened before `from`.
fn depthZero(a: Allocator, toks: []const Token, from: usize, pred: *const fn (Token) bool) Error!?[]usize {
    var out: std.ArrayList(usize) = .empty;
    var depth: usize = 0;
    for (toks[from..], from..) |t, k| {
        if (isClose(t.tag)) {
            if (depth == 0) return null;
            depth -= 1;
            continue;
        }
        if (depth == 0 and pred(t)) try out.append(a, k);
        if (isOpen(t.tag)) depth += 1;
    }
    return out.items;
}

fn isPipe(t: Token) bool {
    return t.tag == .op and (std.mem.eql(u8, t.text, "|>") or std.mem.eql(u8, t.text, "&&") or
        std.mem.eql(u8, t.text, "||") or std.mem.eql(u8, t.text, "++"));
}

fn isColon(t: Token) bool {
    return t.tag == .colon;
}

fn isEquals(t: Token) bool {
    return t.tag == .equals;
}

fn isArrow(t: Token) bool {
    return t.tag == .arrow;
}

fn isComma(t: Token) bool {
    return t.tag == .comma;
}

fn isBar(t: Token) bool {
    return t.tag == .bar;
}

fn isOpenTok(t: Token) bool {
    return isOpen(t.tag);
}

/// Builds the lines that replace one line.
const Lines = struct {
    a: Allocator,
    text: []const u8,
    out: std.ArrayList(u8) = .empty,

    /// Starts a new line at column `col` (from 1).
    fn line(l: *Lines, col: u32) Error!void {
        if (l.out.items.len > 0) try l.out.append(l.a, '\n');
        try l.out.appendNTimes(l.a, ' ', col - 1);
    }

    /// Writes the source of the tokens `toks[from..to]` (inclusive), as one
    /// piece of text with whatever comments are between them.
    fn span(l: *Lines, toks: []const Token, from: usize, to: usize) Error!void {
        try l.out.appendSlice(l.a, l.text[toks[from].start..toks[to].end]);
    }

    fn s(l: *Lines, text: []const u8) Error!void {
        try l.out.appendSlice(l.a, text);
    }
};

/// The lines that replace the line of `toks` (which ends at `end` in
/// `text`), or null when no way of splitting it applies.
fn splitLine(a: Allocator, text: []const u8, toks: []const Token, end: usize) Error!?[]const u8 {
    var l = Lines{ .a = a, .text = text };
    const col0 = toks[0].col;
    const deeper = col0 + indent_width;
    const last = toks.len - 1;
    // What follows the last token: a comment at the end of the line.
    const trailing = std.mem.trimEnd(u8, text[toks[last].end..end], " \r");

    // A line that starts with `,`, `|>` or an opening bracket of a list
    // that goes on below: split what comes after it.
    var s: usize = 0;
    if (toks[0].tag == .comma or isPipe(toks[0]) or (isOpen(toks[0].tag) and closing(toks, 0) == null)) s = 1;
    if (toks[0].tag == .kw_else and toks.len > 1 and toks[1].tag == .kw_if) s = 1;
    if (s > last) return null;

    // Type annotations are left as they are.
    const colons = (try depthZero(a, toks, s, isColon)) orelse return null;
    if (colons.len > 0) return null;

    // 1. `name = body` and `Pattern -> body`: the body on the next line.
    const equals = (try depthZero(a, toks, s, isEquals)).?;
    const arrows = (try depthZero(a, toks, s, isArrow)).?;
    const fns = (try depthZero(a, toks, s, struct {
        fn f(t: Token) bool {
            return t.tag == .kw_fn or t.tag == .kw_if or t.tag == .kw_case;
        }
    }.f)).?;
    const body_break: ?usize = if (equals.len > 0) equals[0] else if (arrows.len > 0 and (fns.len == 0 or fns[0] > arrows[0])) arrows[0] else null;
    // (Not when the body is one token, such as a long string: it would not
    // get shorter.)
    if (body_break) |k| if (k + 1 < last) {
        try l.line(col0);
        try l.span(toks, 0, k);
        try l.line(deeper);
        try l.span(toks, k + 1, last);
        try l.s(trailing);
        return l.out.items;
    };

    // 2. A pipeline (or a chain of `&&`, `||`, `++`): one line per step.
    const pipes = (try depthZero(a, toks, s, isPipe)).?;
    if (pipes.len > 0 and pipes[0] > s) {
        try l.line(col0);
        try l.span(toks, 0, pipes[0] - 1);
        for (pipes, 0..) |p, k| {
            const to = if (k + 1 < pipes.len) pipes[k + 1] - 1 else last;
            try l.line(deeper);
            try l.span(toks, p, to);
        }
        try l.s(trailing);
        return l.out.items;
    }

    // 3. `if c then a else b`: the branches on lines of their own.
    if (toks[s].tag == .kw_if) if (try ifParts(toks, s)) |parts| {
        try l.line(col0);
        try l.span(toks, 0, parts.then_);
        try l.line(deeper);
        try l.span(toks, parts.then_ + 1, parts.else_ - 1);
        try l.line(col0);
        if (s == 1 and toks[0].tag != .kw_else) {
            // `, if ...`: the `else` lines up with the `if`.
            l.out.items.len -= 1;
            try l.line(toks[s].col);
        }
        if (parts.else_ + 1 <= last and toks[parts.else_ + 1].tag == .kw_if) {
            try l.span(toks, parts.else_, last);
        } else {
            try l.s("else");
            try l.line(deeper);
            try l.span(toks, parts.else_ + 1, last);
        }
        try l.s(trailing);
        return l.out.items;
    };

    // 4. A list, record or tuple: one item per line, with leading commas.
    const opens = (try depthZero(a, toks, s, isOpenTok)).?;
    for (opens) |o| {
        const c = closing(toks, o) orelse continue;
        // `(fn a, b -> ...)`: those are a lambda's parameters (see 5).
        if (o + 1 < c and toks[o + 1].tag == .kw_fn) continue;
        const commas = (try depthZero(a, toks[0..c], o + 1, isComma)) orelse continue;
        if (commas.len == 0) continue;
        // A record update `{ r | a = 1, b = 2 }`.
        const bars = (try depthZero(a, toks[0..c], o + 1, isBar)).?;
        const is_update = toks[o].tag == .lbrace and bars.len > 0 and bars[0] < commas[0];
        const at_start = o == s;
        const bracket_col: u32 = if (at_start) toks[o].col else deeper;
        if (at_start) {
            try l.line(col0);
            if (o > 0) try l.span(toks, 0, o - 1);
            if (o > 0) try l.s(" ");
        } else {
            try l.line(col0);
            try l.span(toks, 0, o - 1);
            try l.line(bracket_col);
        }
        try l.s(toks[o].text);
        try l.s(" ");
        if (is_update) {
            try l.span(toks, o + 1, bars[0] - 1);
            try l.line(bracket_col + indent_width);
            try l.span(toks, bars[0], commas[0] - 1);
        } else {
            try l.span(toks, o + 1, commas[0] - 1);
        }
        for (commas, 0..) |cm, k| {
            const to = if (k + 1 < commas.len) commas[k + 1] - 1 else c - 1;
            try l.line(if (is_update) bracket_col + indent_width else bracket_col);
            try l.s(", ");
            try l.span(toks, cm + 1, to);
        }
        try l.line(bracket_col);
        try l.s(toks[c].text);
        if (c < last) {
            if (at_start) {
                try l.s(" ");
                try l.span(toks, c + 1, last);
            } else {
                try l.line(deeper);
                try l.span(toks, c + 1, last);
            }
        }
        try l.s(trailing);
        return l.out.items;
    }

    // 5. `(fn x -> body)`: the body on a line of its own.
    if (toks[s].tag == .lparen and s + 1 <= last and toks[s + 1].tag == .kw_fn and closing(toks, s) == last) {
        const arrow = for (toks[s + 1 .. last], s + 1..) |t, k| {
            if (t.tag == .arrow) break k;
        } else return null;
        if (arrow + 1 >= last) return null;
        try l.line(col0);
        try l.span(toks, 0, arrow);
        try l.line(deeper);
        try l.span(toks, arrow + 1, last - 1);
        try l.line(if (s == 0) col0 else toks[s].col);
        try l.s(")");
        try l.s(trailing);
        return l.out.items;
    }

    // 6. `(f a b)`: the call inside split as below, the `)` on its own line.
    if (toks[s].tag == .lparen and closing(toks, s) == last and last > s + 2) {
        if (try callArgs(a, toks[0..last], s + 1)) |args| if (args.len >= 1) {
            try l.line(col0);
            try l.span(toks, 0, args[0] - 1);
            for (args, 0..) |arg, k| {
                const to = if (k + 1 < args.len) args[k + 1] - 1 else last - 1;
                try l.line(toks[s].col + indent_width);
                try l.span(toks, arg, to);
            }
            try l.line(toks[s].col);
            try l.s(")");
            try l.s(trailing);
            return l.out.items;
        };
    }

    // 7. A call `f a b c`: one argument per line. (Not a call with one
    // argument of one token, such as a long string.)
    if (try callArgs(a, toks, s)) |args| if (args.len > 1 or (args.len == 1 and args[0] < last)) {
        try l.line(col0);
        try l.span(toks, 0, args[0] - 1);
        for (args, 0..) |arg, k| {
            const to = if (k + 1 < args.len) args[k + 1] - 1 else last;
            try l.line(deeper);
            try l.span(toks, arg, to);
        }
        try l.s(trailing);
        return l.out.items;
    };
    return null;
}

const IfParts = struct { then_: usize, else_: usize };

/// The `then` and `else` of the `if` at `at`, when the whole `if` is on
/// this line.
fn ifParts(toks: []const Token, at: usize) Error!?IfParts {
    var depth: usize = 0;
    var ifs: usize = 0;
    var then_: ?usize = null;
    for (toks[at..], at..) |t, k| {
        if (isOpen(t.tag)) depth += 1;
        if (isClose(t.tag)) {
            if (depth == 0) return null;
            depth -= 1;
        }
        if (depth != 0) continue;
        switch (t.tag) {
            .kw_if => ifs += 1,
            .kw_then => if (ifs == 1 and then_ == null) {
                then_ = k;
            },
            .kw_else => {
                if (ifs == 1) return if (then_) |th| .{ .then_ = th, .else_ = k } else null;
                ifs -= 1;
            },
            else => {},
        }
    }
    return null;
}

/// The first token of each argument when `toks[from..]` is a call: a name
/// followed by arguments that are each one token or one bracketed group,
/// with no operator between them. Null when it is not such a call.
fn callArgs(a: Allocator, toks: []const Token, from_tok: usize) Error!?[]usize {
    // `try f a b` is a call of `f`.
    const is_try = toks[from_tok].tag == .lower and std.mem.eql(u8, toks[from_tok].text, "try");
    const from = if (is_try and from_tok + 1 < toks.len) from_tok + 1 else from_tok;
    const head = toks[from];
    if (head.tag != .lower and head.tag != .qlower and head.tag != .upper) return null;
    var args: std.ArrayList(usize) = .empty;
    var k = from + 1;
    while (k < toks.len) {
        const t = toks[k];
        switch (t.tag) {
            .lower, .upper, .qlower, .int, .float, .string, .char, .underscore => {
                try args.append(a, k);
                k += 1;
                // `x.field` belongs to its argument.
                while (k < toks.len and toks[k].tag == .dot_field) k += 1;
            },
            .lparen, .lbrack, .lbrace => {
                try args.append(a, k);
                k = (closing(toks, k) orelse return null) + 1;
                while (k < toks.len and toks[k].tag == .dot_field) k += 1;
            },
            else => return null,
        }
    }
    return args.items;
}
