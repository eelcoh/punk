//! punk's build. The compiler is Roc's (the `roc` dependency, a pinned commit
//! of eelcoh/roc), built with punk's seam in it (`-Dpunk=src/`), and
//! installed as `zig-out/bin/punk`.
//!
//!     zig build          the compiler, as zig-out/bin/punk
//!     zig build test     the translator's unit tests

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const roc = b.dependency("roc", .{
        .target = target,
        .optimize = optimize,
        .punk = b.path("src"),
    });
    const install = b.addInstallArtifact(roc.artifact("roc"), .{ .dest_sub_path = "punk" });
    b.getInstallStep().dependOn(&install.step);

    // Roc's builtins, which src/punk/gen_llms.py and gen_stdlib.py read.
    const builtins = b.addInstallFile(roc.path("src/build/roc/Builtin.roc"), "share/roc/Builtin.roc");
    b.getInstallStep().dependOn(&builtins.step);

    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/punk/test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const test_step = b.step("test", "Run the translator's unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
