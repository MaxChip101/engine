const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gl_bindings = @import("zigglgen").generateModule(b, .{
        .api = .gl,
        .version = .@"4.3",
        .profile = .core,
    });

    const sdl = b.dependency("sdl", .{
        .optimize = optimize,
        .target = target,
    });

    const zmath = b.dependency("zmath", .{
        .optimize = optimize,
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "engine",
        //.linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    exe.root_module.addImport("gl", gl_bindings);
    exe.root_module.addImport("sdl3", sdl.module("sdl3"));
    exe.root_module.addImport("zmath", zmath.module("root"));

    // exe.use_lld = true;
    // exe.use_llvm = true;

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
