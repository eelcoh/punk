//! punkroc: Roc's compiler shows types in its own syntax (`List(Str)`,
//! `Try(I64, Str)`, `{ name: Str }`, `[Circle(F64)]`, `where [...]`). This
//! turns such a type, as it appears in an error message, into the way it is
//! written in punk (`List Str`, `Result Int Str`, `{ name : Str }`,
//! `(Circle Float)`).
//!
//! The type checker's `where` clauses mostly say that a value comes from a
//! literal: a type variable that a number can be is Elm's `number`, and one
//! that a string literal can be is `Str`. Other requirements stay, in a
//! `where` clause of their own.

const std = @import("std");

const Allocator = std.mem.Allocator;

/// `text` (one type in Roc's syntax, possibly over several lines) in punk's
/// syntax, owned by `a`. Null when it is not a type this understands, or
/// when nothing changes.
pub fn punkType(a: Allocator, text: []const u8) Allocator.Error!?[]u8 {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const ar = arena.allocator();
    var p = Parser{ .a = ar, .src = text };
    const parsed = p.parseTop() catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Syntax => return null,
    };

    var w = Writer{ .a = ar };
    try w.assignNames(parsed);
    try w.write(parsed.ty, .top);
    var leftover = false;
    for (parsed.wheres) |wh| if (!w.absorbed(wh.var_name)) {
        leftover = true;
        break;
    };
    if (leftover) {
        try w.out.appendSlice(ar, " where ");
        var first = true;
        for (parsed.wheres) |wh| {
            if (w.absorbed(wh.var_name)) continue;
            if (!first) try w.out.appendSlice(ar, ", ");
            first = false;
            try w.out.appendSlice(ar, w.varName(wh.var_name));
            try w.out.append(ar, '.');
            try w.out.appendSlice(ar, try camel(ar, wh.method));
            try w.out.appendSlice(ar, " : ");
            try w.write(wh.ty, .top);
        }
    }
    if (std.mem.eql(u8, w.out.items, text)) return null;
    return try a.dupe(u8, w.out.items);
}

const Type = union(enum) {
    /// A type name or a type variable, as Roc writes it.
    name: []const u8,
    app: struct { head: []const u8, args: []*Type },
    func: struct { args: []*Type, effectful: bool, ret: *Type },
    record: struct { fields: []Field, ext: ?[]const u8 },
    tags: struct { tags: []Tag, ext: ?[]const u8 },
    tuple: []*Type,
};

const Field = struct { name: []const u8, optional: bool, ty: *Type };
const Tag = struct { name: []const u8, args: []*Type };
const Where = struct { var_name: []const u8, method: []const u8, ty: *Type };
const Parsed = struct { ty: *Type, wheres: []Where };

const ParseError = error{ Syntax, OutOfMemory };

const Parser = struct {
    a: Allocator,
    src: []const u8,
    i: usize = 0,

    fn skip(p: *Parser) void {
        while (p.i < p.src.len and std.ascii.isWhitespace(p.src[p.i])) p.i += 1;
    }

    fn peek(p: *Parser, s: []const u8) bool {
        p.skip();
        return std.mem.startsWith(u8, p.src[p.i..], s);
    }

    fn eat(p: *Parser, s: []const u8) bool {
        if (!p.peek(s)) return false;
        p.i += s.len;
        return true;
    }

    fn expect(p: *Parser, s: []const u8) ParseError!void {
        if (!p.eat(s)) return error.Syntax;
    }

    fn new(p: *Parser, t: Type) ParseError!*Type {
        const ptr = try p.a.create(Type);
        ptr.* = t;
        return ptr;
    }

    /// A name: letters, digits, `_` and `.` (qualified names).
    fn ident(p: *Parser) ParseError![]const u8 {
        p.skip();
        const start = p.i;
        while (p.i < p.src.len and (std.ascii.isAlphanumeric(p.src[p.i]) or p.src[p.i] == '_' or p.src[p.i] == '.')) {
            // `..` is a row extension, not part of a name.
            if (p.src[p.i] == '.' and p.i + 1 < p.src.len and p.src[p.i + 1] == '.') break;
            p.i += 1;
        }
        if (p.i == start) return error.Syntax;
        return p.src[start..p.i];
    }

    fn parseTop(p: *Parser) ParseError!Parsed {
        const ty = try p.parseType();
        var wheres: std.ArrayList(Where) = .empty;
        if (p.eat("where")) {
            try p.expect("[");
            while (!p.eat("]")) {
                const v = try p.ident();
                // `a.from_numeral` is one name to `ident`.
                const dot = std.mem.findScalar(u8, v, '.') orelse return error.Syntax;
                try p.expect(":");
                const t = try p.parseType();
                try wheres.append(p.a, .{ .var_name = v[0..dot], .method = v[dot + 1 ..], .ty = t });
                if (!p.eat(",")) {
                    try p.expect("]");
                    break;
                }
            }
        }
        p.skip();
        if (p.i != p.src.len) return error.Syntax;
        return .{ .ty = ty, .wheres = wheres.items };
    }

    /// A type, with a function's arguments separated by commas.
    fn parseType(p: *Parser) ParseError!*Type {
        var args: std.ArrayList(*Type) = .empty;
        try args.append(p.a, try p.parseAtom());
        while (true) {
            if (p.peek("->") or p.peek("=>")) {
                const effectful = p.peek("=>");
                p.i += 2;
                const ret = try p.parseType();
                return p.new(.{ .func = .{ .args = args.items, .effectful = effectful, .ret = ret } });
            }
            // Only a function's arguments come in a comma list here; a
            // comma that ends a list of arguments belongs to the caller.
            if (!p.commaStartsFunctionArg()) break;
            _ = p.eat(",");
            try args.append(p.a, try p.parseAtom());
        }
        if (args.items.len != 1) return error.Syntax;
        return args.items[0];
    }

    /// Whether a `,` here separates the arguments of a function type (an
    /// arrow follows before the enclosing bracket closes).
    fn commaStartsFunctionArg(p: *Parser) bool {
        if (!p.peek(",")) return false;
        var depth: usize = 0;
        var j = p.i + 1;
        while (j < p.src.len) : (j += 1) {
            switch (p.src[j]) {
                '(', '[', '{' => depth += 1,
                ')', ']', '}' => {
                    if (depth == 0) return false;
                    depth -= 1;
                },
                ',' => if (depth == 0) continue,
                // The next requirement of a `where` clause.
                ':' => if (depth == 0) return false,
                '-', '=' => if (depth == 0 and j + 1 < p.src.len and p.src[j + 1] == '>') return true,
                else => {},
            }
            if (depth == 0 and std.mem.startsWith(u8, p.src[j..], "where")) return false;
        }
        return false;
    }

    fn parseAtom(p: *Parser) ParseError!*Type {
        if (p.eat("(")) {
            if (p.eat(")")) return p.new(.{ .tuple = &.{} });
            var elems: std.ArrayList(*Type) = .empty;
            try elems.append(p.a, try p.parseType());
            while (p.eat(",")) try elems.append(p.a, try p.parseType());
            try p.expect(")");
            if (elems.items.len == 1) return elems.items[0];
            return p.new(.{ .tuple = elems.items });
        }
        if (p.eat("{")) {
            var fields: std.ArrayList(Field) = .empty;
            var ext: ?[]const u8 = null;
            while (!p.eat("}")) {
                if (p.eat("..")) {
                    ext = if (p.peek("}")) "" else try p.ident();
                    try p.expect("}");
                    break;
                }
                const name = try p.ident();
                const optional = p.eat("?");
                if (!optional) try p.expect(":");
                try fields.append(p.a, .{ .name = name, .optional = optional, .ty = try p.parseType() });
                if (!p.eat(",")) {
                    try p.expect("}");
                    break;
                }
            }
            return p.new(.{ .record = .{ .fields = fields.items, .ext = ext } });
        }
        if (p.eat("[")) {
            var tags: std.ArrayList(Tag) = .empty;
            var ext: ?[]const u8 = null;
            while (!p.eat("]")) {
                if (p.eat("..")) {
                    ext = if (p.peek("]")) "" else try p.ident();
                    try p.expect("]");
                    break;
                }
                const name = try p.ident();
                var args: std.ArrayList(*Type) = .empty;
                if (p.src.len > p.i and p.src[p.i] == '(') {
                    p.i += 1;
                    try args.append(p.a, try p.parseType());
                    while (p.eat(",")) try args.append(p.a, try p.parseType());
                    try p.expect(")");
                }
                try tags.append(p.a, .{ .name = name, .args = args.items });
                if (!p.eat(",")) {
                    try p.expect("]");
                    break;
                }
            }
            return p.new(.{ .tags = .{ .tags = tags.items, .ext = ext } });
        }
        const name = try p.ident();
        // `List(Str)`: the argument list follows the name directly.
        if (p.i < p.src.len and p.src[p.i] == '(') {
            p.i += 1;
            var args: std.ArrayList(*Type) = .empty;
            try args.append(p.a, try p.parseType());
            while (p.eat(",")) try args.append(p.a, try p.parseType());
            try p.expect(")");
            return p.new(.{ .app = .{ .head = name, .args = args.items } });
        }
        return p.new(.{ .name = name });
    }
};

/// How much a type written in a place needs parentheses.
const Place = enum {
    /// Anywhere a whole type goes.
    top,
    /// An argument of a function type: a function needs parentheses.
    fn_arg,
    /// An argument of a type or tag: anything with spaces needs them.
    arg,
};

const Writer = struct {
    a: Allocator,
    out: std.ArrayList(u8) = .empty,
    /// Type variables with a new name (`number`, or `Str` for a string
    /// literal's), by their Roc name.
    renamed: std.StringHashMapUnmanaged([]const u8) = .empty,

    fn assignNames(w: *Writer, parsed: Parsed) Allocator.Error!void {
        var numbers: usize = 0;
        for (parsed.wheres) |wh| {
            if (w.renamed.contains(wh.var_name)) continue;
            if (std.mem.eql(u8, wh.method, "from_numeral") or std.mem.eql(u8, wh.method, "fromNumeral")) {
                const name = if (numbers == 0) "number" else try std.fmt.allocPrint(w.a, "number{d}", .{numbers});
                numbers += 1;
                try w.renamed.put(w.a, wh.var_name, name);
            } else if (std.mem.eql(u8, wh.method, "from_quote") or std.mem.eql(u8, wh.method, "fromQuote")) {
                try w.renamed.put(w.a, wh.var_name, "Str");
            }
        }
    }

    /// Whether the requirements on `v` are all said by its new name.
    fn absorbed(w: *Writer, v: []const u8) bool {
        return w.renamed.contains(v);
    }

    fn varName(w: *Writer, v: []const u8) []const u8 {
        return w.renamed.get(v) orelse v;
    }

    fn s(w: *Writer, text: []const u8) Allocator.Error!void {
        try w.out.appendSlice(w.a, text);
    }

    fn write(w: *Writer, t: *const Type, place: Place) Allocator.Error!void {
        switch (t.*) {
            .name => |n| try w.s(w.varName(typeName(n))),
            .app => |app| {
                if (app.args.len == 0) return w.s(typeName(app.head));
                if (place == .arg) try w.s("(");
                try w.s(if (std.mem.eql(u8, app.head, "Try")) "Result" else typeName(app.head));
                for (app.args) |arg| {
                    try w.s(" ");
                    try w.write(arg, .arg);
                }
                if (place == .arg) try w.s(")");
            },
            .func => |f| {
                if (place != .top) try w.s("(");
                for (f.args, 0..) |arg, i| {
                    if (i > 0) try w.s(", ");
                    try w.write(arg, .fn_arg);
                }
                try w.s(if (f.effectful) " => " else " -> ");
                try w.write(f.ret, .top);
                if (place != .top) try w.s(")");
            },
            .tuple => |elems| {
                try w.s("(");
                for (elems, 0..) |el, i| {
                    if (i > 0) try w.s(", ");
                    try w.write(el, .top);
                }
                try w.s(")");
            },
            .record => |r| {
                if (r.fields.len == 0 and r.ext == null) return w.s("{}");
                try w.s("{ ");
                if (r.ext) |ext| {
                    try w.s(if (ext.len == 0) "a" else w.varName(ext));
                    try w.s(" | ");
                }
                for (r.fields, 0..) |f, i| {
                    if (i > 0) try w.s(", ");
                    try w.s(try camel(w.a, f.name));
                    try w.s(if (f.optional) " ? " else " : ");
                    try w.write(f.ty, .top);
                }
                try w.s(" }");
            },
            .tags => |u| {
                if (maybeArg(u)) |arg| {
                    if (place == .arg) try w.s("(");
                    try w.s("Maybe ");
                    try w.write(arg, .arg);
                    if (place == .arg) try w.s(")");
                    return;
                }
                if (isOrder(u)) return w.s("Order");
                try w.s("(");
                for (u.tags, 0..) |tag, i| {
                    if (i > 0) try w.s(" | ");
                    try w.s(tag.name);
                    for (tag.args) |arg| {
                        try w.s(" ");
                        try w.write(arg, .arg);
                    }
                }
                if (u.ext) |ext| {
                    try w.s(if (u.tags.len > 0) " | .." else "..");
                    try w.s(w.varName(ext));
                }
                try w.s(")");
            },
        }
    }
};

/// punk's names for Roc's number types.
fn typeName(n: []const u8) []const u8 {
    if (std.mem.eql(u8, n, "I64")) return "Int";
    if (std.mem.eql(u8, n, "F64")) return "Float";
    return n;
}

/// The `a` of `[Just(a), Nothing]`, which is punk's `Maybe a`.
fn maybeArg(u: anytype) ?*Type {
    if (u.ext != null or u.tags.len != 2) return null;
    var just: ?*Type = null;
    var nothing = false;
    for (u.tags) |tag| {
        if (std.mem.eql(u8, tag.name, "Just") and tag.args.len == 1) just = tag.args[0];
        if (std.mem.eql(u8, tag.name, "Nothing") and tag.args.len == 0) nothing = true;
    }
    return if (nothing) just else null;
}

fn isOrder(u: anytype) bool {
    if (u.ext != null or u.tags.len != 3) return false;
    for (u.tags) |tag| {
        if (tag.args.len != 0) return false;
        if (!std.mem.eql(u8, tag.name, "LT") and !std.mem.eql(u8, tag.name, "EQ") and !std.mem.eql(u8, tag.name, "GT")) return false;
    }
    return true;
}

/// `from_numeral` as `fromNumeral`.
fn camel(a: Allocator, name: []const u8) Allocator.Error![]const u8 {
    if (std.mem.findScalar(u8, name, '_') == null or name.len == 0 or name[0] == '_') return name;
    var out: std.ArrayList(u8) = .empty;
    var up = false;
    for (name) |c| {
        if (c == '_') {
            up = true;
            continue;
        }
        try out.append(a, if (up) std.ascii.toUpper(c) else c);
        up = false;
    }
    return out.items;
}
