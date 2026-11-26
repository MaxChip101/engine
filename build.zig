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

    const engine_mod = b.addModule("engine", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    engine_mod.addImport("gl", gl_bindings);
    engine_mod.addImport("sdl3", sdl.module("sdl3"));
    engine_mod.addImport("zmath", zmath.module("root"));

    const mod_tests = b.addTest(.{
        .root_module = engine_mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_mod_tests.step);
}
