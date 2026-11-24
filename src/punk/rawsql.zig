//! Rule P303: the SQL of `Sql.query` fits the tables of the program.
//!
//! `Sql.query` is the escape hatch for what the query language can't say
//! yet, but its SQL is still text the compiler can read (P301 makes it a
//! literal). This file reads it, without a database, and checks what a
//! program can get wrong without Postgres noticing until the query runs:
//!
//! - every table it names is a `table` of the program (`FROM links`),
//! - every column it names is a column of those tables (`links.url`, `url`),
//!   and a bare column is in only one of them,
//! - each parameter `$n` has the type of the column it meets
//!   (`created > $1` wants `Sql.posix`, `INSERT INTO links (id, url) VALUES
//!   ($1, $2)` wants the types of `id` and `url`, `LIMIT $1` an `Sql.int`),
//!   and the list gives exactly the parameters the SQL uses.
//!
//! It is a reader of the SQL people write by hand, not a full SQL parser:
//! what it does not understand it leaves to Postgres, which checks the rest
//! when the query is prepared (a column of a subquery or a `WITH` is not
//! checked, a parameter with a cast `$1::text` takes the cast's type).

const std = @import("std");
const Allocator = std.mem.Allocator;
const tr = @import("translate.zig");
const query = @import("query.zig");
const Emitter = tr.Emitter;
const Expr = tr.Expr;
const Error = tr.Error;
const Table = query.Table;
const Column = query.Column;

const Tok = struct {
    kind: Kind,
    /// The text in the source: an identifier without its quotes, `$3`,
    /// `::`, an operator, a punctuation mark.
    text: []const u8,

    const Kind = enum { ident, quoted, param, string, number, op, punct };

    fn is(t: Tok, word: []const u8) bool {
        return t.kind == .ident and std.ascii.eqlIgnoreCase(t.text, word);
    }

    fn punctIs(t: Tok, c: []const u8) bool {
        return (t.kind == .punct or t.kind == .op) and std.mem.eql(u8, t.text, c);
    }
};

/// The SQL of a punk string literal (with its quotes) as tokens. Escapes of
/// the punk string (`\"`, `\n`) are read as what they stand for.
fn tokenize(a: Allocator, literal: []const u8) Allocator.Error![]Tok {
    var toks: std.ArrayList(Tok) = .empty;
    var s = literal;
    // Strip the quotes: `"..."` or `"""..."""`.
    if (std.mem.startsWith(u8, s, "\"\"\"") and s.len >= 6) {
        s = s[3 .. s.len - 3];
    } else if (s.len >= 2 and s[0] == '"') {
        s = s[1 .. s.len - 1];
    }
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        if (c == '\\' and i + 1 < s.len and s[i + 1] == '"') {
            // A quoted identifier: `\"user\"`.
            const start = i + 2;
            var j = start;
            while (j + 1 < s.len and !(s[j] == '\\' and s[j + 1] == '"')) j += 1;
            try toks.append(a, .{ .kind = .quoted, .text = s[start..j] });
            i = @min(j + 2, s.len);
        } else if (c == '\\') {
            i += 2; // `\n`, `\t`: white space
        } else if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            i += 1;
        } else if (c == '-' and i + 1 < s.len and s[i + 1] == '-') {
            while (i < s.len and s[i] != '\n' and !(s[i] == '\\' and i + 1 < s.len and s[i + 1] == 'n')) i += 1;
        } else if (c == '/' and i + 1 < s.len and s[i + 1] == '*') {
            const end = std.mem.findPos(u8, s, i + 2, "*/") orelse s.len;
            i = @min(end + 2, s.len);
        } else if (c == '\'') {
            var j = i + 1;
            while (j < s.len) : (j += 1) {
                if (s[j] == '\'') {
                    if (j + 1 < s.len and s[j + 1] == '\'') {
                        j += 1;
                        continue;
                    }
                    break;
                }
            }
            try toks.append(a, .{ .kind = .string, .text = s[i..@min(j + 1, s.len)] });
            i = @min(j + 1, s.len);
        } else if (c == '$' and i + 1 < s.len and std.ascii.isDigit(s[i + 1])) {
            var j = i + 1;
            while (j < s.len and std.ascii.isDigit(s[j])) j += 1;
            try toks.append(a, .{ .kind = .param, .text = s[i..j] });
            i = j;
        } else if (c == '$' and i + 1 < s.len and s[i + 1] == '$') {
            // A dollar-quoted string: `$$ ... $$`.
            const end = std.mem.findPos(u8, s, i + 2, "$$") orelse s.len;
            try toks.append(a, .{ .kind = .string, .text = s[i..@min(end + 2, s.len)] });
            i = @min(end + 2, s.len);
        } else if (std.ascii.isDigit(c)) {
            var j = i;
            while (j < s.len and (std.ascii.isAlphanumeric(s[j]) or s[j] == '.')) j += 1;
            try toks.append(a, .{ .kind = .number, .text = s[i..j] });
            i = j;
        } else if (std.ascii.isAlphabetic(c) or c == '_') {
            var j = i;
            while (j < s.len and (std.ascii.isAlphanumeric(s[j]) or s[j] == '_' or s[j] == '$')) j += 1;
            try toks.append(a, .{ .kind = .ident, .text = s[i..j] });
            i = j;
        } else if (c == ':' and i + 1 < s.len and s[i + 1] == ':') {
            try toks.append(a, .{ .kind = .punct, .text = s[i .. i + 2] });
            i += 2;
        } else if (std.mem.findScalar(u8, "=<>!~+-*/%^|&@#", c) != null) {
            var j = i;
            while (j < s.len and std.mem.findScalar(u8, "=<>!~+-*/%^|&@#", s[j]) != null) {
                // `*` alone is `SELECT *`; keep `-` before a digit apart.
                if (j > i and s[j] == '-' and j + 1 < s.len and std.ascii.isDigit(s[j + 1])) break;
                j += 1;
            }
            try toks.append(a, .{ .kind = .op, .text = s[i..j] });
            i = j;
        } else {
            try toks.append(a, .{ .kind = .punct, .text = s[i .. i + 1] });
            i += 1;
        }
    }
    return toks.items;
}

/// Words of SQL that are never a column: keywords, and type names after
/// `::` that are more than one word.
const keywords = [_][]const u8{
    "all",               "and",          "any",       "array",    "as",         "asc",       "between",        "by",
    "case",              "cast",         "collate",   "conflict", "constraint", "cross",     "current_date",   "current_time",
    "current_timestamp", "current_user", "default",   "delete",   "desc",       "distinct",  "do",             "else",
    "end",               "escape",       "except",    "exists",   "false",      "fetch",     "filter",         "first",
    "for",               "from",         "full",      "group",    "having",     "ilike",     "in",             "inner",
    "insert",            "intersect",    "interval",  "into",     "is",         "isnull",    "join",           "last",
    "lateral",           "left",         "like",      "limit",    "local",      "localtime", "localtimestamp", "materialized",
    "natural",           "next",         "not",       "nothing",  "notnull",    "null",      "nulls",          "of",
    "offset",            "on",           "only",      "or",       "order",      "outer",     "over",           "partition",
    "precision",         "recursive",    "returning", "right",    "row",        "rows",      "select",         "session_user",
    "set",               "similar",      "skip",      "some",     "symmetric",  "table",     "then",           "ties",
    "time",              "timestamp",    "to",        "true",     "union",      "unknown",   "update",         "user",
    "using",             "values",       "varying",   "when",     "where",      "window",    "with",           "without",
    "zone",              "excluded",     "locked",    "nowait",   "share",      "key",       "double",         "character",
    "unbounded",         "preceding",    "following", "current",  "range",      "groups",    "ordinality",     "uescape",
    "year",              "month",        "day",       "hour",     "minute",     "second",    "epoch",          "leading",
    "trailing",          "both",
};

fn isKeyword(t: Tok) bool {
    if (t.kind != .ident) return false;
    for (keywords) |k| if (std.ascii.eqlIgnoreCase(t.text, k)) return true;
    return false;
}

/// A table or a name the query gives a set of rows: `links`, `links AS l`,
/// a `WITH` or a subquery (`table` null: its columns are not known here).
const Rel = struct { name: []const u8, quoted: bool, table: ?*const Table };

fn nameIs(t: Tok, name: []const u8, quoted: bool) bool {
    if (t.kind == .quoted or quoted) return std.mem.eql(u8, t.text, name);
    return std.ascii.eqlIgnoreCase(t.text, name);
}

fn findTable(e: *Emitter, t: Tok) ?*const Table {
    var it = e.tables.valueIterator();
    while (it.next()) |table| {
        const plain = table.*.plain();
        if (t.kind == .quoted) {
            if (std.mem.eql(u8, plain, t.text)) return table.*;
        } else if (std.ascii.eqlIgnoreCase(plain, t.text)) return table.*;
    }
    return null;
}

fn findColumn(t: *const Table, tok: Tok) ?*const Column {
    for (t.columns) |*c| {
        if (tok.kind == .quoted) {
            if (std.mem.eql(u8, c.plain, tok.text)) return c;
        } else if (std.ascii.eqlIgnoreCase(c.plain, tok.text)) return c;
    }
    return null;
}

fn sqlColumnNames(a: Allocator, t: *const Table) Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (t.columns, 0..) |c, i| {
        if (i > 0) try out.appendSlice(a, ", ");
        try out.appendSlice(a, c.plain);
    }
    return out.items;
}

/// The names of the tables of the module, sorted.
fn tableNames(e: *Emitter) Allocator.Error![]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var it = e.tables.valueIterator();
    while (it.next()) |table| try names.append(e.a, table.*.plain());
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lt(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.order(u8, x, y) == .lt;
        }
    }.lt);
    return std.mem.join(e.a, ", ", names.items);
}

/// Ends the list of tables after FROM.
fn endsFrom(t: Tok) bool {
    if (t.kind == .punct and (std.mem.eql(u8, t.text, ")") or std.mem.eql(u8, t.text, ";"))) return true;
    for ([_][]const u8{ "where", "group", "order", "limit", "offset", "having", "returning", "set", "values", "union", "intersect", "except", "on", "using", "window", "for", "fetch" }) |w| if (t.is(w)) return true;
    return false;
}

fn startsJoin(t: Tok) bool {
    for ([_][]const u8{ "join", "left", "right", "inner", "outer", "full", "cross", "natural", "lateral" }) |w| if (t.is(w)) return true;
    return false;
}

/// Checks the SQL of one `Sql.query`. `literal` is the string as written
/// (a slice of the source, so errors point into it), `params` the list of
/// parameters when it is written as a list, and `sql_module` how the file
/// calls the module `Sql` (`Sql`, or the `as` name).
pub fn check(e: *Emitter, sql_module: []const u8, literal: []const u8, params: ?*Expr) Error!void {
    const a = e.a;
    const toks = try tokenize(a, literal);
    if (toks.len == 0) return;
    var rels: std.ArrayList(Rel) = .empty;
    // Token positions that name something rather than use a column: tables,
    // their aliases, names of `WITH`s, aliases of output columns.
    const defines = try a.alloc(bool, toks.len);
    @memset(defines, false);
    // The column each token that names one stands for.
    const cols = try a.alloc(?*const Column, toks.len);
    @memset(cols, null);
    var out_aliases: std.ArrayList([]const u8) = .empty;

    // Names of `WITH name AS (...)`, which the query uses as tables.
    for (toks, 0..) |t, i| {
        if ((t.kind == .ident or t.kind == .quoted) and i + 2 < toks.len and toks[i + 1].is("as") and toks[i + 2].punctIs("(")) {
            if (isKeyword(t)) continue;
            try rels.append(a, .{ .name = t.text, .quoted = t.kind == .quoted, .table = null });
            defines[i] = true;
        }
    }

    // Tables after FROM, JOIN, INTO and UPDATE, with their aliases;
    // subqueries with theirs.
    var insert: ?struct { table: *const Table, columns: []const ?*const Column, values_at: usize } = null;
    var paren_alias: std.ArrayList(usize) = .empty; // depths of `FROM (` subqueries
    // For each open parenthesis, whether it is a function's (`extract(epoch
    // FROM created)`), where FROM is not a clause.
    var calls: std.ArrayList(bool) = .empty;
    var depth: usize = 0;
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        const t = toks[i];
        if (t.punctIs("(")) {
            depth += 1;
            try calls.append(a, i > 0 and toks[i - 1].kind == .ident and !isKeyword(toks[i - 1]));
            continue;
        }
        if (t.punctIs(")")) {
            _ = calls.pop();
            if (paren_alias.items.len > 0 and paren_alias.items[paren_alias.items.len - 1] == depth) {
                _ = paren_alias.pop();
                var k = i + 1;
                if (k < toks.len and toks[k].is("as")) k += 1;
                if (k < toks.len and (toks[k].kind == .quoted or (toks[k].kind == .ident and !isKeyword(toks[k])))) {
                    try rels.append(a, .{ .name = toks[k].text, .quoted = toks[k].kind == .quoted, .table = null });
                    defines[k] = true;
                }
            }
            depth -|= 1;
            continue;
        }
        // `AS name` after an expression names an output column.
        if (t.is("as") and i + 1 < toks.len and (toks[i + 1].kind == .ident or toks[i + 1].kind == .quoted) and !(i + 2 < toks.len and toks[i + 2].punctIs("("))) {
            if (!isKeyword(toks[i + 1]) or toks[i + 1].kind == .quoted) {
                defines[i + 1] = true;
                try out_aliases.append(a, toks[i + 1].text);
            }
            continue;
        }
        const starts = t.is("from") or t.is("join") or t.is("into") or (t.is("update") and !(i > 0 and toks[i - 1].is("do")) and !(i > 0 and toks[i - 1].is("for")));
        if (!starts) continue;
        if (calls.items.len > 0 and calls.items[calls.items.len - 1]) continue;
        // The tables of this clause, separated by commas after FROM.
        var k = i + 1;
        while (k < toks.len) {
            if (toks[k].is("only") or toks[k].is("lateral")) k += 1;
            if (k >= toks.len) break;
            const name = toks[k];
            if (name.punctIs("(")) {
                // A subquery: its alias comes after its `)`.
                try paren_alias.append(a, depth + 1);
                break;
            }
            if (name.kind != .ident and name.kind != .quoted) break;
            if (name.kind == .ident and isKeyword(name)) break;
            if (!t.is("into") and k + 1 < toks.len and toks[k + 1].punctIs("(")) break; // a function: `FROM generate_series(...)`
            defines[k] = true;
            var rel: Rel = .{ .name = name.text, .quoted = name.kind == .quoted, .table = null };
            const is_with = for (rels.items) |r| {
                if (r.table == null and nameIs(name, r.name, r.quoted)) break true;
            } else false;
            if (!is_with) {
                const table = findTable(e, name) orelse {
                    return e.errAtRule(name.text, .sql_tables, if (e.tables.count() == 0)
                        try std.fmt.allocPrint(a, "there is no table '{s}' in this module. Declare it, as in 'table {s} : Row', so that punk knows its columns and makes it in the schema", .{ name.text, name.text })
                    else
                        try std.fmt.allocPrint(a, "there is no table '{s}' in this module (it has {s})", .{ name.text, try tableNames(e) }));
                };
                rel.table = table;
            }
            try rels.append(a, rel);
            k += 1;
            // `AS l`, or `l`.
            if (k < toks.len and toks[k].is("as")) k += 1;
            if (k < toks.len and (toks[k].kind == .quoted or (toks[k].kind == .ident and !isKeyword(toks[k]) and !startsJoin(toks[k])))) {
                try rels.append(a, .{ .name = toks[k].text, .quoted = toks[k].kind == .quoted, .table = rel.table });
                defines[k] = true;
                k += 1;
            }
            // INSERT INTO t (a, b, c) VALUES (...)
            if (t.is("into") and rel.table != null and k < toks.len and toks[k].punctIs("(")) {
                var columns: std.ArrayList(?*const Column) = .empty;
                var m = k + 1;
                while (m < toks.len and !toks[m].punctIs(")")) : (m += 1) {
                    if (toks[m].kind == .ident or toks[m].kind == .quoted) {
                        const c = findColumn(rel.table.?, toks[m]) orelse return unknownColumn(e, rel.table.?, toks[m]);
                        cols[m] = c;
                        defines[m] = true;
                        try columns.append(a, c);
                    }
                }
                var v = m;
                while (v < toks.len and !toks[v].is("values") and !toks[v].is("select")) v += 1;
                insert = .{ .table = rel.table.?, .columns = columns.items, .values_at = v };
            }
            if (!t.is("from") or k >= toks.len or !toks[k].punctIs(",")) break;
            k += 1;
        }
    }

    // Every other name is a column of one of the tables.
    var has_unknown_rel = false;
    for (rels.items) |r| if (r.table == null) {
        has_unknown_rel = true;
    };
    i = 0;
    while (i < toks.len) : (i += 1) {
        const t = toks[i];
        if (defines[i] or cols[i] != null) continue;
        if (t.kind != .ident and t.kind != .quoted) continue;
        if (t.kind == .ident and isKeyword(t)) continue;
        if (i + 1 < toks.len and toks[i + 1].punctIs("(")) continue; // a function
        if (i > 0 and toks[i - 1].punctIs("::")) continue; // a type
        if (i + 2 < toks.len and toks[i + 1].punctIs(".")) {
            // `pg_catalog.now()`: a function of a schema.
            if (i + 3 < toks.len and toks[i + 3].punctIs("(")) {
                i += 2;
                continue;
            }
            // `l.url`, `links.*`
            const q = for (rels.items) |r| {
                if (nameIs(t, r.name, r.quoted)) break r;
            } else {
                return e.errAtRule(t.text, .sql_tables, try std.fmt.allocPrint(a, "'{s}' is not a table or an alias of this query", .{t.text}));
            };
            const col_tok = toks[i + 2];
            if (q.table) |table| if (col_tok.kind == .ident or col_tok.kind == .quoted) {
                const c = findColumn(table, col_tok) orelse return unknownColumn(e, table, col_tok);
                cols[i] = c;
                cols[i + 2] = c;
            };
            i += 2;
            continue;
        }
        // A bare column: in exactly one of the tables.
        var found: ?*const Column = null;
        var found_in: ?*const Table = null;
        for (rels.items) |r| {
            const table = r.table orelse continue;
            if (found_in == table) continue;
            if (findColumn(table, t)) |c| {
                if (found_in) |other| {
                    return e.errAtRule(t.text, .sql_tables, try std.fmt.allocPrint(a, "both {s} and {s} have a column '{s}': write which one, as in {s}.{s}", .{ other.plain(), table.plain(), t.text, table.plain(), t.text }));
                }
                found = c;
                found_in = table;
            }
        }
        if (found) |c| {
            cols[i] = c;
            continue;
        }
        const is_alias = for (out_aliases.items) |n| {
            if (std.mem.eql(u8, n, t.text)) break true;
        } else false;
        if (is_alias or has_unknown_rel) continue;
        var real: ?*const Table = null;
        var n_real: usize = 0;
        for (rels.items) |r| if (r.table) |table| if (real != table) {
            real = table;
            n_real += 1;
        };
        if (n_real == 1) return unknownColumn(e, real.?, t);
        if (n_real == 0) return e.errAtRule(t.text, .sql_tables, try std.fmt.allocPrint(a, "'{s}' is not a column of a table of this query: the query reads no table", .{t.text}));
        return e.errAtRule(t.text, .sql_tables, try std.fmt.allocPrint(a, "none of the tables of this query has a column '{s}'", .{t.text}));
    }

    // The type of each parameter, from the column it meets.
    var max: usize = 0;
    var first_at = std.AutoHashMapUnmanaged(usize, []const u8).empty;
    for (toks) |t| if (t.kind == .param) {
        const n = std.fmt.parseInt(usize, t.text[1..], 10) catch continue;
        max = @max(max, n);
        if (!first_at.contains(n)) try first_at.put(a, n, t.text);
    };
    const meets = try a.alloc(?Meet, max + 1);
    @memset(meets, null);
    for (toks, 0..) |t, k| {
        if (t.kind != .param) continue;
        const n = std.fmt.parseInt(usize, t.text[1..], 10) catch continue;
        if (meets[n] != null) continue;
        if (k + 1 < toks.len and toks[k + 1].punctIs("::")) continue; // `$1::text`: the cast says
        if (k > 0 and (toks[k - 1].is("limit") or toks[k - 1].is("offset"))) {
            meets[n] = .limit;
            continue;
        }
        if (k >= 2 and isComparison(toks[k - 1])) if (cols[k - 2]) |c| {
            meets[n] = .{ .column = .{ .c = c, .compare = !toks[k - 1].punctIs("=") or !isSet(toks, k - 2) } };
            continue;
        };
        if (k + 2 < toks.len and isComparison(toks[k + 1])) if (cols[k + 2]) |c| {
            meets[n] = .{ .column = .{ .c = c, .compare = true } };
            continue;
        };
    }
    // VALUES ($1, $2, ...), (...) of an INSERT.
    if (insert) |ins| {
        var k = ins.values_at + 1;
        var pos: usize = 0;
        var d: usize = 0;
        while (k < toks.len) : (k += 1) {
            const t = toks[k];
            if (t.punctIs("(")) {
                d += 1;
                if (d == 1) pos = 0;
                continue;
            }
            if (t.punctIs(")")) {
                if (d == 0) break;
                d -= 1;
                continue;
            }
            if (d == 0 and !t.punctIs(",")) break;
            if (d == 1 and t.punctIs(",")) {
                pos += 1;
                continue;
            }
            if (d == 1 and t.kind == .param and pos < ins.columns.len) {
                const alone = toks[k - 1].punctIs("(") or toks[k - 1].punctIs(",");
                const next_ok = k + 1 < toks.len and (toks[k + 1].punctIs(")") or toks[k + 1].punctIs(","));
                if (!alone or !next_ok) continue;
                const n = std.fmt.parseInt(usize, t.text[1..], 10) catch continue;
                if (meets[n] == null) if (ins.columns[pos]) |c| {
                    meets[n] = .{ .column = .{ .c = c, .compare = false } };
                };
            }
        }
    }

    const list_expr = params orelse return;
    const list = switch (query.unparen(list_expr).*) {
        .list => |l| l,
        else => return,
    };
    // Every parameter from $1 to the last is used, and the list has them all.
    var n: usize = 1;
    while (n <= max) : (n += 1) if (!first_at.contains(n)) {
        return e.errAtRule(first_at.get(max).?, .sql_tables, try std.fmt.allocPrint(a, "the SQL uses ${d} but not ${d}: number the parameters from $1 on, without gaps", .{ max, n }));
    };
    if (list.len != max) {
        const at = if (list.len > max) exprAt(list[max]) orelse literal else literal;
        const says = if (max == 0) try a.dupe(u8, "uses no parameters") else if (max == 1) try a.dupe(u8, "uses $1") else try std.fmt.allocPrint(a, "uses $1 to ${d}", .{max});
        return e.errAtRule(at, .sql_tables, try std.fmt.allocPrint(a, "the SQL {s}, so the list has {d} {s}, not {d}", .{ says, max, if (max == 1) "parameter" else "parameters", list.len }));
    }
    for (list, 1..) |item, k| {
        const meet = meets[k] orelse continue;
        const given = paramKind(item, sql_module) orelse continue;
        const at = exprAt(item) orelse literal;
        switch (meet) {
            .limit => if (!std.mem.eql(u8, given.kind, "int") or given.nullable) {
                return e.errAtRule(at, .sql_tables, try std.fmt.allocPrint(a, "${d} is a LIMIT or OFFSET, so it is {s}.int, not {s}", .{ k, sql_module, try given.name(a, sql_module) }));
            },
            .column => |m| {
                const want = kindOf(m.c.ty.base);
                if (given.nullable and !m.c.ty.nullable) {
                    if (m.compare) {
                        return e.errAtRule(at, .sql_tables, try std.fmt.allocPrint(a, "${d} is compared with the column '{s}', which is never empty, and NULL is not equal to anything: give a value with {s}.{s}, or test for NULL with IS NULL", .{ k, m.c.plain, sql_module, want }));
                    }
                    return e.errAtRule(at, .sql_tables, try std.fmt.allocPrint(a, "${d} goes into the column '{s}', which can't be empty (it is not a Maybe): give a value with {s}.{s}", .{ k, m.c.plain, sql_module, want }));
                }
                if (given.kind.len > 0 and !std.mem.eql(u8, given.kind, want)) {
                    const verb = if (m.compare) "meets" else "goes into";
                    return e.errAtRule(at, .sql_tables, try std.fmt.allocPrint(a, "${d} {s} the column '{s}', {s}, so it is {s}.{s}, not {s}", .{ k, verb, m.c.plain, try m.c.ty.storage().an(a), sql_module, want, try given.name(a, sql_module) }));
                }
            },
        }
    }
}

const Meet = union(enum) {
    limit,
    column: struct { c: *const Column, compare: bool },
};

fn isComparison(t: Tok) bool {
    if (t.kind == .op) for ([_][]const u8{ "=", "<>", "!=", "<", ">", "<=", ">=" }) |op| if (std.mem.eql(u8, t.text, op)) return true;
    return t.is("like") or t.is("ilike");
}

/// Whether the column at `k` is set (`SET a = $1, b = $2`) rather than
/// compared: the clause it is in started with SET.
fn isSet(toks: []const Tok, k: usize) bool {
    var j = k;
    while (j > 0) {
        j -= 1;
        if (toks[j].is("set")) return true;
        if (toks[j].is("where") or toks[j].is("select") or toks[j].is("on") or toks[j].is("having")) return false;
    }
    return false;
}

fn unknownColumn(e: *Emitter, table: *const Table, t: Tok) Error {
    return e.errAtRule(t.text, .sql_tables, try std.fmt.allocPrint(e.a, "the table '{s}' has no column '{s}' (it has {s})", .{ table.plain(), t.text, try sqlColumnNames(e.a, table) }));
}

/// The name of the `Sql` function for a column of this type.
fn kindOf(b: query.ColType.Base) []const u8 {
    return switch (b) {
        .str => "text",
        .int => "int",
        .float => "float",
        .bool => "bool",
        .posix => "posix",
        .uuid => "uuid",
        .dec => "dec",
        .json => "json",
    };
}

/// What a parameter in the list is: `Sql.text id` is "text", `Sql.null` is
/// a NULL of any kind (kind ""), `Sql.nullable Sql.int n` is a nullable
/// "int". Null for anything else (a variable, a function of the program).
const Given = struct {
    kind: []const u8,
    nullable: bool,

    fn name(g: Given, a: Allocator, module: []const u8) Allocator.Error![]const u8 {
        if (g.kind.len == 0) return std.fmt.allocPrint(a, "{s}.null", .{module});
        if (g.nullable) return std.fmt.allocPrint(a, "{s}.nullable {s}.{s}", .{ module, module, g.kind });
        return std.fmt.allocPrint(a, "{s}.{s}", .{ module, g.kind });
    }
};

fn sqlMember(x_in: *Expr, module: []const u8) ?[]const u8 {
    const x = query.unparen(x_in);
    if (x.* != .ident) return null;
    const n = x.ident;
    if (n.len <= module.len + 1 or !std.mem.startsWith(u8, n, module) or n[module.len] != '.') return null;
    return n[module.len + 1 ..];
}

fn paramKind(x_in: *Expr, module: []const u8) ?Given {
    const x = query.unparen(x_in);
    if (sqlMember(x, module)) |m| {
        if (std.mem.eql(u8, m, "null")) return .{ .kind = "", .nullable = true };
        return null;
    }
    if (x.* != .app) return null;
    const m = sqlMember(x.app.func, module) orelse return null;
    if (std.mem.eql(u8, m, "nullable")) {
        if (x.app.args.len == 0) return null;
        const inner = sqlMember(x.app.args[0], module) orelse return null;
        return .{ .kind = inner, .nullable = true };
    }
    for ([_][]const u8{ "text", "int", "float", "bool", "posix", "uuid", "dec", "json" }) |k| if (std.mem.eql(u8, m, k)) return .{ .kind = k, .nullable = false };
    return null;
}

/// Some text of the source in an expression, to point an error at.
fn exprAt(x_in: *Expr) ?[]const u8 {
    const x = query.unparen(x_in);
    return switch (x.*) {
        .app => |ap| exprAt(ap.func),
        else => query.exprText(x),
    };
}
