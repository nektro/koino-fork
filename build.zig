const std = @import("std");
const deps = @import("./deps.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.option(std.builtin.Mode, "mode", "") orelse .Debug;
    const disable_llvm = b.option(bool, "disable_llvm", "use the non-llvm zig codegen") orelse false;

    const exe = b.addExecutable(.{
        .name = "koino",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = mode,
    });
    deps.addAllTo(exe);
    exe.use_llvm = !disable_llvm;
    exe.use_lld = !disable_llvm;
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
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = mode,
    });
    deps.addAllTo(test_exe);
    test_exe.use_llvm = !disable_llvm;
    test_exe.use_lld = !disable_llvm;

    const test_step = b.step("test", "Run all the tests");
    const test_run = b.addRunArtifact(test_exe);
    test_run.has_side_effects = true;
    test_step.dependOn(&test_run.step);
}
