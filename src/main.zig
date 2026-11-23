const std = @import("std");
const heap = std.heap;

const sdl = @import("sdl3");
const zm = @import("zmath");

const rd = @import("renderer.zig");
const windows = @import("windows.zig");
const input = @import("input.zig");

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

const skybox_verts = [_]rd.Vertex{
    // Front face (+Z)  -> cell (3,1)
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .uv = .{ 1.0, 2.0 / 3.0 } },
    .{ .pos = .{ 0.5, -0.5, 0.5 }, .uv = .{ 0.75, 2.0 / 3.0 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .uv = .{ 0.75, 1.0 / 3.0 } },
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .uv = .{ 1.0, 1.0 / 3.0 } },

    // Back face (-Z)  -> cell (1,1), the center
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .uv = .{ 0.5, 2.0 / 3.0 } },
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .uv = .{ 0.25, 2.0 / 3.0 } },
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .uv = .{ 0.25, 1.0 / 3.0 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .uv = .{ 0.5, 1.0 / 3.0 } },

    // Left face (-X)  -> cell (0,1)
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .uv = .{ 0.25, 2.0 / 3.0 } },
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .uv = .{ 0.0, 2.0 / 3.0 } },
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .uv = .{ 0.0, 1.0 / 3.0 } },
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .uv = .{ 0.25, 1.0 / 3.0 } },

    // Right face (+X)  -> cell (2,1)
    .{ .pos = .{ 0.5, -0.5, 0.5 }, .uv = .{ 0.75, 2.0 / 3.0 } },
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .uv = .{ 0.5, 2.0 / 3.0 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .uv = .{ 0.5, 1.0 / 3.0 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .uv = .{ 0.75, 1.0 / 3.0 } },

    // Top face (+Y)  -> cell (1,0); its bottom edge (v=1/3) touches the -Z face
    .{ .pos = .{ -0.5, 0.5, 0.5 }, .uv = .{ 0.25, 0.0 } },
    .{ .pos = .{ 0.5, 0.5, 0.5 }, .uv = .{ 0.5, 0.0 } },
    .{ .pos = .{ 0.5, 0.5, -0.5 }, .uv = .{ 0.5, 1.0 / 3.0 } },
    .{ .pos = .{ -0.5, 0.5, -0.5 }, .uv = .{ 0.25, 1.0 / 3.0 } },

    // Bottom face (-Y)  -> cell (1,2); its top edge (v=2/3) touches the -Z face
    .{ .pos = .{ -0.5, -0.5, -0.5 }, .uv = .{ 0.25, 2.0 / 3.0 } },
    .{ .pos = .{ 0.5, -0.5, -0.5 }, .uv = .{ 0.5, 2.0 / 3.0 } },
    .{ .pos = .{ 0.5, -0.5, 0.5 }, .uv = .{ 0.5, 1.0 } },
    .{ .pos = .{ -0.5, -0.5, 0.5 }, .uv = .{ 0.25, 1.0 } },
};

const cube_indices = [_]u32{
    0, 1, 2, 2, 3, 0, // Front
    4, 5, 6, 6, 7, 4, // Back
    8, 9, 10, 10, 11, 8, // Left
    12, 13, 14, 14, 15, 12, // Right
    16, 17, 18, 18, 19, 16, // Top
    20, 21, 22, 22, 23, 20, // Bottom
};

const skybox_indices = [_]u32{
    0, 2, 1, 2, 0, 3, // Front
    4, 6, 5, 6, 4, 7, // Back
    8, 10, 9, 10, 8, 11, // Left
    12, 14, 13, 14, 12, 15, // Right
    16, 18, 17, 18, 16, 19, // Top
    20, 22, 21, 22, 20, 23, // Bottom
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

    const window = try windows.Window.init(
        allocator,
        .{
            .flags = .{},
            .vsync = .Adaptive,
            .anti_aliasing = .{
                .msaa = .{
                    .samples = 4,
                },
            },
        },
    );
    defer window.deinit();

    const renderer = try rd.Renderer.init(
        allocator,
        .{
            .anti_aliasing = .{
                .msaa = .{
                    .sample_shading = true,
                    .min_sample_shading = 1.0,
                },
            },
        },
    );
    defer renderer.deinit();

    renderer.setBlend(.Alpha);

    const checker = rd.Texture.checkerboard(
        8,
        .{ 255, 0, 255, 255 },
        .{ 20, 20, 20, 255 },
    );
    defer checker.deinit();

    const sky_cubemap = try rd.Cubemap.fromPngAtlas(
        allocator,
        @embedFile("res/skybox.png"),
        .{
            .{ 0.5, 1.0 / 3.0, 0.75, 2.0 / 3.0 }, // +X
            .{ 0.0, 1.0 / 3.0, 0.25, 2.0 / 3.0 }, // -X
            .{ 0.25, 0.0, 0.5, 1.0 / 3.0 }, // +Y
            .{ 0.25, 2.0 / 3.0, 0.5, 1.0 }, // -Y
            .{ 0.25, 1.0 / 3.0, 0.5, 2.0 / 3.0 }, // +Z
            .{ 0.75, 1.0 / 3.0, 1.0, 2.0 / 3.0 }, // -Z
        },
        .{ .filter = .Linear, .mipmaps = false, .repeat = false },
    );
    defer sky_cubemap.deinit();

    const shader: rd.Shader = try .init(
        allocator,
        &.{@embedFile("shaders/vertex.glsl")},
        &.{@embedFile("shaders/fragment.glsl")},
    );
    defer shader.deinit();

    const skybox_shader: rd.Shader = try .init(
        allocator,
        &.{@embedFile("shaders/skybox_vertex.glsl")},
        &.{@embedFile("shaders/skybox_fragment.glsl")},
    );
    defer skybox_shader.deinit();

    var mesh: rd.Mesh = try .init(
        allocator,
        &cube_verts,
        &cube_indices,
        .{
            .normal_gen = .Smooth,
        },
    );
    defer mesh.deinit();

    var skybox: rd.Mesh = try .init(
        allocator,
        &skybox_verts,
        &skybox_indices,
        .{
            .normal_gen = .Smooth,
        },
    );
    defer skybox.deinit();

    var cam_pos: zm.Vec = .{ 0.0, 1.0, 2.0, 0.0 };
    var cam_rot: zm.Vec = .{ 0.0, 0.0, 0.0, 0.0 };

    var prev_time = window.time();
    const move_speed: f32 = 2.0;
    const turn_speed: f32 = 2.0;
    const mouse_sensitivity: f32 = 0.0025;

    while (window.pollEvents()) {
        if (window.input.isPressed(.Escape)) {
            window.setRelativeMouse(!window.relativeMouse());
        }

        const now = window.time();
        const raw_dt = now - prev_time;
        prev_time = now;
        const dt = @min(@max(raw_dt, 0.0), 0.1);

        const dx = window.input.mouse_delta[0];
        const dy = window.input.mouse_delta[1];

        var yaw_input: f32 = 0.0;
        var pitch_input: f32 = 0.0;
        if (window.input.isDown(.Left)) yaw_input -= 1.0;
        if (window.input.isDown(.Right)) yaw_input += 1.0;
        if (window.input.isDown(.Up)) pitch_input += 1.0;
        if (window.input.isDown(.Down)) pitch_input -= 1.0;

        cam_rot[1] -= dx * mouse_sensitivity + yaw_input * turn_speed * dt;
        cam_rot[0] -= dy * mouse_sensitivity - pitch_input * turn_speed * dt;

        const rot = zm.quatFromRollPitchYawV(cam_rot);

        const cam_forward = zm.rotate(rot, .{ 0.0, 0.0, -1.0, 0.0 });
        const cam_right = zm.rotate(rot, .{ 1.0, 0.0, 0.0, 0.0 });

        var flat_forward = @Vector(4, f32){ cam_forward[0], 0.0, cam_forward[2], 0.0 };
        var flat_right = @Vector(4, f32){ cam_right[0], 0.0, cam_right[2], 0.0 };

        const f_len = @sqrt(flat_forward[0] * flat_forward[0] + flat_forward[2] * flat_forward[2]);
        if (f_len > 0.0001) flat_forward /= @splat(f_len);

        const r_len = @sqrt(flat_right[0] * flat_right[0] + flat_right[2] * flat_right[2]);
        if (r_len > 0.0001) flat_right /= @splat(r_len);

        var wish_dir = @Vector(4, f32){ 0.0, 0.0, 0.0, 0.0 };
        if (window.input.isDown(.W)) wish_dir += flat_forward;
        if (window.input.isDown(.S)) wish_dir -= flat_forward;
        if (window.input.isDown(.D)) wish_dir += flat_right;
        if (window.input.isDown(.A)) wish_dir -= flat_right;
        if (window.input.isDown(.LeftShift)) wish_dir[1] -= 1.0;
        if (window.input.isDown(.Space)) wish_dir[1] += 1.0;

        const w_sq = wish_dir[0] * wish_dir[0] + wish_dir[1] * wish_dir[1] + wish_dir[2] * wish_dir[2];
        if (w_sq > 0.0001) {
            const w_len = @sqrt(w_sq);
            wish_dir /= @splat(w_len);
            cam_pos += wish_dir * @as(@Vector(4, f32), @splat(move_speed * dt));
        }

        const inv_rot = zm.conjugate(rot);
        const rot_mat = zm.quatToMat(inv_rot);
        const trans_mat = zm.translationV(-cam_pos);
        const view = zm.mul(trans_mat, rot_mat);

        const s = window.size();
        const aspect = @as(f32, @floatFromInt(s[0])) / @as(f32, @floatFromInt(s[1]));

        const persp = zm.perspectiveFovRhGl(std.math.degreesToRadians(60.0), aspect, 0.01, 100.0);
        const view_proj = zm.matToArr(zm.mul(view, persp));

        const stationary_view_proj = zm.matToArr(zm.mul(rot_mat, persp));

        renderer.beginFrame(window);

        renderer.setDepthState(.{});
        renderer.setCullState(.{});
        renderer.drawMesh(
            view_proj,
            mesh,
            zm.matToArr(zm.identity()),
            checker,
            shader,
        );

        renderer.setDepthState(.{ .func = .LessEqual, .write = false });
        // renderer.setCullState(.{ .mode = .Front }); // only set to front if using regular cube indices
        renderer.drawCubemap(stationary_view_proj, skybox, zm.matToArr(zm.identity()), sky_cubemap, skybox_shader);

        // double-sided mesh (leaves, cloth)
        //renderer.setCullState(.{ .mode = .none });

        // UI / overlay
        //renderer.setDepthState(.{ .test_enabled = false });

        window.swap();
    }
}
