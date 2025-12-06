const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zCrop",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    exe.root_module.addIncludePath(b.path("libs"));
    exe.linkSystemLibrary("SDL2");
    exe.addCSourceFile(.{
        .file = b.path("libs/stb_impl.c"),
        .flags = &.{"-std=c99"},
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the image cropping tool");
    run_step.dependOn(&run_cmd.step);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addIncludePath(b.path("libs"));

    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    unit_tests.addCSourceFile(.{
        .file = b.path("libs/stb_impl.c"),
        .flags = &.{"-std=c99"},
    });

    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    const check_step = b.step("check", "Check compilation (for ZLS)");
    check_step.dependOn(&exe.step);
}