//! How punk's numbers behave where Roc's would crash. This is the one place
//! that decides it, so the choice can change without touching the rest of
//! the translator.
//!
//! The choice for now (PROVISIONAL, roadmap decision 4): Elm's behaviour.
//! Dividing an integer by zero gives 0 instead of crashing: `7 // 0 == 0`,
//! `7 % 0 == 0`, `modBy 0 7 == 0`, `remainderBy 0 7 == 0`. (Elm itself
//! crashes on `modBy 0`; punk does not.)
//!
//! Not done yet: wrapping on overflow of `+`, `-` and `*`. The translator
//! does not know the types of values, and only Roc's integer types have
//! `plus_wrap`, so `a + b` keeps Roc's meaning, which crashes on overflow.
//!
//! The explicit `Int.checked*` functions return `Result` using Roc's checked
//! I64 builtins. They take the right operand first for pipelines.

const std = @import("std");
const elm = @import("elm.zig");

pub const Policy = enum {
    /// Elm's behaviour: division by zero gives 0.
    elm,
    /// Roc's behaviour: division by zero crashes.
    roc,
};

/// The behaviour punk uses.
pub const policy: Policy = .elm;

/// The helper an arithmetic operator becomes (`a // b` is
/// `punk_int_div(a, b)`), or null when it stays Roc's operator.
pub fn operator(op: []const u8) ?elm.Helper {
    if (policy != .elm) return null;
    if (std.mem.eql(u8, op, "//")) return int_div;
    if (std.mem.eql(u8, op, "%")) return int_rem;
    return null;
}

/// The helper for a named number function (`mod_by`, `Int.checked_add`), or null.
pub fn helper(snake_name: []const u8) ?elm.Helper {
    return named_helpers.get(snake_name);
}

/// The helper called `name` (`punk_int_div`), or null.
pub fn helperByName(name: []const u8) ?elm.Helper {
    for ([_]elm.Helper{ int_div, int_rem }) |h| if (std.mem.eql(u8, h.name, name)) return h;
    for (named_helpers.values()) |h| if (std.mem.eql(u8, h.name, name)) return h;
    return null;
}

/// `if b == 0 { 0 } else { ... }` with policy `.elm`, nothing with `.roc`.
fn guard(comptime divisor: []const u8, comptime body: []const u8) []const u8 {
    return if (policy == .elm) "if " ++ divisor ++ " == 0 { 0 } else { " ++ body ++ " }" else body;
}

const int_div: elm.Helper = .{ .name = "punk_int_div", .arity = 2, .def = "punk_int_div = |a, b| " ++ guard("b", "a // b") };
const int_rem: elm.Helper = .{ .name = "punk_int_rem", .arity = 2, .def = "punk_int_rem = |a, b| " ++ guard("b", "a % b") };

/// Elm's `modBy n x`: the result has the sign of `n`, `modBy 3 -1 == 2`.
const mod_by: elm.Helper = .{
    .name = "punk_mod_by",
    .arity = 2,
    .def = "punk_mod_by = |n, x| " ++ guard("n", "if x % n != 0 and (x % n < 0) != (n < 0) { x % n + n } else { x % n }"),
};

/// Elm's `remainderBy n x`: the result has the sign of `x`, `remainderBy 3 -1 == -1`.
const remainder_by: elm.Helper = .{ .name = "punk_remainder_by", .arity = 2, .def = "punk_remainder_by = |n, x| " ++ guard("n", "x % n") };

const named_helpers = std.StaticStringMap(elm.Helper).initComptime(.{
    .{ "mod_by", mod_by },
    .{ "remainder_by", remainder_by },
    .{ "Int.checked_add", checked("punk_int_checked_add", "plus_try") },
    .{ "Int.checked_sub", checked("punk_int_checked_sub", "minus_try") },
    .{ "Int.checked_mul", checked("punk_int_checked_mul", "times_try") },
    .{ "Int.checked_div", checked("punk_int_checked_div", "div_try") },
});

fn checked(comptime name: []const u8, comptime builtin_name: []const u8) elm.Helper {
    return .{
        .name = name,
        .arity = 2,
        .def = name ++ " = |right, left| I64." ++ builtin_name ++ "(left, right)",
    };
}
