const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    //run
    const exe = b.addExecutable("zig-aabb", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    addPackages(exe);

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    //test
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest("src/main.zig");
    tests.setTarget(target);
    tests.setBuildMode(mode);
    addPackages(tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&tests.step);
}

fn addPackages(lib: *std.build.LibExeObjStep) void {
    lib.addPackage(.{
        .name = "zalgebra",
        .path = .{ .path = "libs/zalgebra/src/main.zig" },
    });
}
