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
        // Roc's coverage steps pull in kcov on linux-aarch64; punk needs none.
        .coverage = false,
    });
    const libexec: std.Build.InstallDir = .{ .custom = "libexec" };
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rocBinary(roc), libexec, "punk").step);
    b.getInstallStep().dependOn(&b.addInstallBinFile(b.path("tools/release/punk.sh"), "punk").step);

    // Buffer formatting uses punk's formatter directly, with the file's import context.
    const fmt_stdin = b.addExecutable(.{ .name = "punk-fmt", .root_module = b.createModule(.{
        .root_source_file = b.path("src/punk/fmt_stdin.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    b.getInstallStep().dependOn(&b.addInstallArtifact(fmt_stdin, .{ .dest_dir = .{ .override = libexec } }).step);

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

/// The `roc` binary that Roc's build installs. On macOS Roc installs a copy
/// with its exports stripped (an install of a file, not of the artifact), so
/// `roc.artifact("roc")` would not find it there.
fn rocBinary(roc: *std.Build.Dependency) std.Build.LazyPath {
    for (roc.builder.install_tls.step.dependencies.items) |step| {
        if (step.cast(std.Build.Step.InstallArtifact)) |inst| {
            if (std.mem.eql(u8, inst.artifact.name, "roc")) return inst.artifact.getEmittedBin();
        }
        if (step.cast(std.Build.Step.InstallFile)) |inst| {
            if (inst.dir == .bin and std.mem.eql(u8, inst.dest_rel_path, "roc")) return inst.source;
        }
    }
    // Not configured yet (Zig first fetches lazy dependencies) or gone:
    // this reports which artifacts there are.
    return roc.artifact("roc").getEmittedBin();
}
