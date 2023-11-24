const std = @import("std");
const deps = @import("./deps.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "koino",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    deps.addAllTo(exe);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const test_exe = b.addTest(.{
        .name = "test",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    deps.addAllTo(test_exe);
    const test_step = b.step("test", "Run all the tests");
    const test_run = b.addRunArtifact(test_exe);
    test_step.dependOn(&test_run.step);
}
