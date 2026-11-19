const std = @import("std");
const heap = std.heap;

const sdl = @import("sdl3");

const math = @import("math.zig");
const rd = @import("renderer.zig");

const cube_verts = [_]rd.Vertex{
    // Front face (+Z)
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .uv = .{ 0.0, 0.0 } },
    .{ .pos = .{ 0.5, -0.5, 0.5 }, .uv = .{ 1.0, 0.0 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .uv = .{ 1.0, 1.0 } },
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .uv = .{ 0.0, 1.0 } },

    // Back face (-Z)
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .uv = .{ 0.0, 0.0 } },
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .uv = .{ 1.0, 0.0 } },
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .uv = .{ 1.0, 1.0 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .uv = .{ 0.0, 1.0 } },

    // Left face (-X)
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .uv = .{ 0.0, 0.0 } },
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .uv = .{ 1.0, 0.0 } },
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .uv = .{ 1.0, 1.0 } },
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .uv = .{ 0.0, 1.0 } },

    // Right face (+X)
    .{ .pos = .{ 0.5, -0.5, 0.5 }, .uv = .{ 0.0, 0.0 } },
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .uv = .{ 1.0, 0.0 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .uv = .{ 1.0, 1.0 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .uv = .{ 0.0, 1.0 } },

    // Top face (+Y)
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .uv = .{ 0.0, 0.0 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .uv = .{ 1.0, 0.0 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .uv = .{ 1.0, 1.0 } },
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .uv = .{ 0.0, 1.0 } },

    // Bottom face (-Y)
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .uv = .{ 0.0, 0.0 } },
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .uv = .{ 1.0, 0.0 } },
    .{ .pos = .{ 0.5, -0.5, 0.5 }, .uv = .{ 1.0, 1.0 } },
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .uv = .{ 0.0, 1.0 } },
};

const cube_indices = [_]u32{
    0, 1, 2, 2, 3, 0, // Front
    4, 5, 6, 6, 7, 4, // Back
    8, 9, 10, 10, 11, 8, // Left
    12, 13, 14, 14, 15, 12, // Right
    16, 17, 18, 18, 19, 16, // Top
    20, 21, 22, 22, 23, 20, // Bottom
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    _ = io;
    var gpa = heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }

    const r = try rd.Renderer.init(
        allocator,
        .{
            .flags = sdl.SDL_WINDOW_RESIZABLE,
            .vsync = false,
            .anti_aliasing = .{
                .msaa = .{
                    .samples = 4,
                    .sample_shading = true,
                    .min_sample_shading = 1.0,
                },
            },
        },
    );
    defer r.deinit();

    const checker = rd.Texture.checkerboard(
        16,
        .{ 255, 0, 255, 255 },
        .{ 20, 20, 20, 255 },
    );
    defer checker.deinit();

    const shader: rd.Shader = try .init(
        allocator,
        &.{@embedFile("shaders/vertex.glsl")},
        &.{@embedFile("shaders/fragment.glsl")},
    );
    defer shader.deinit();

    var mesh: rd.Mesh = try .init(
        allocator,
        &cube_verts,
        &cube_indices,
        .{
            .normal_gen = .smooth,
        },
    );
    defer mesh.deinit();

    while (r.pollEvents()) {
        const t = r.time();
        const s = r.size();
        const aspect = @as(f32, @floatFromInt(s[0])) / @as(f32, @floatFromInt(s[1]));

        const eye: math.Vec3 = .{ @cos(t * 0.5) * 10.0, 2.5, @sin(t * 0.5) * 2.0 };

        const view = math.lookAt(eye, .{ 0, 0, 0 }, .{ 0, 1, 0 });
        const proj = math.perspective(std.math.degreesToRadians(60.0), aspect, 0.1, 100.0);

        r.beginFrame(math.mul(proj, view));
        r.drawMesh(mesh, math.mul(math.translate(0, 0, 0), math.identity()), checker, shader);
        r.endFrame();
    }
}
