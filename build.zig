const std = @import("std");
const Sdk = @import("libs/SDL.zig/build.zig");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    const sdk = Sdk.init(b, null);

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // link SDL2 as a shared library
    sdk.link(exe, .dynamic);

    exe.addModule("sdl2", sdk.getWrapperModule());

    b.installArtifact(exe);

    const run_artifact = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_artifact.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_artifact.step);
}
