const std = @import("std");
const mem = std.mem;
const log = std.log;

const sdl = @import("sdl3");
const gl = @import("gl");

pub const Mat4 = [16]f32;
// might need later but not now
// pub const identity: Mat4 = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 };

pub const Rgba = [4]u8;

// helper functions for computing normals
fn sub(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
fn cross(a: [3]f32, b: [3]f32) [3]f32 {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}
fn normalize(v: [3]f32) [3]f32 {
    const len = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (len == 0) return .{ 0, 0, 1 };
    return .{ v[0] / len, v[1] / len, v[2] / len };
}
fn hasNormal(n: [3]f32) bool {
    return n[0] != 0 or n[1] != 0 or n[2] != 0;
}

fn logSdlError() void {
    log.err("[SDL] error: {s}", .{sdl.SDL_GetError()});
}

pub const Vertex = extern struct {
    pos: [3]f32,
    uv: [2]f32 = .{ 0.0, 0.0 },
    normal: [3]f32 = .{ 0.0, 0.0, 0.0 },
};

pub const Texture = struct {
    id: c_uint,
    width: u32,
    height: u32,

    pub const Filter = enum {
        nearest,
        linear,
    };

    pub const Options = struct {
        filter: Filter = .linear,
        mipmaps: bool = true,
        repeat: bool = true,
    };

    const Self = @This();

    pub fn fromRgba8(width: u32, height: u32, pixels: []const u8, options: Options) Self {
        std.debug.assert(pixels.len == @as(usize, width) * height * 4);

        var id: c_uint = 0;
        gl.GenTextures(1, @ptrCast(&id));
        gl.BindTexture(gl.TEXTURE_2D, id);

        gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, @intCast(width), @intCast(height), 0, gl.RGBA, gl.UNSIGNED_BYTE, pixels.ptr);

        const wrap: c_int = if (options.repeat) gl.REPEAT else gl.CLAMP_TO_EDGE;
        const mag: c_int = if (options.filter == .linear) gl.LINEAR else gl.NEAREST;
        const min: c_int = switch (options.filter) {
            .linear => if (options.mipmaps) gl.LINEAR_MIPMAP_LINEAR else gl.LINEAR,
            .nearest => if (options.mipmaps) gl.NEAREST_MIPMAP_NEAREST else gl.NEAREST,
        };
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, min);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, mag);
        if (options.mipmaps) gl.GenerateMipmap(gl.TEXTURE_2D);

        return .{
            .id = id,
            .width = width,
            .height = height,
        };
    }

    pub fn fromBmp(data: []const u8, options: Options) !Self {
        const io = sdl.SDL_IOFromConstMem(data.ptr, data.len) orelse {
            logSdlError();
            return error.ImageLoadFailed;
        };

        const loaded = sdl.SDL_LoadBMP_IO(io, true) orelse {
            logSdlError();
            return error.ImageLoadFailed;
        };

        return fromSurface(loaded, options);
    }

    pub fn fromPng(data: []const u8, options: Options) !Self {
        const io = sdl.SDL_IOFromConstMem(data.ptr, data.len) orelse {
            logSdlError();
            return error.ImageLoadFailed;
        };

        const loaded = sdl.SDL_LoadPNG_IO(io, true) orelse {
            logSdlError();
            return error.ImageLoadFailed;
        };

        return fromSurface(loaded, options);
    }

    pub fn checkerboard(comptime cells: usize, on_col: Rgba, off_col: Rgba) Self {
        const dim = cells * cells;
        var px: [dim * dim * 4]u8 = undefined;
        for (0..dim) |y| {
            for (0..dim) |x| {
                const on = ((x / cells) + (y / cells)) % 2 == 0;
                const i = (y * dim + x) * 4;
                px[i..][0..4].* = if (on) on_col else off_col;
            }
        }
        return fromRgba8(dim, dim, &px, .{ .filter = .nearest, .mipmaps = false });
    }

    pub fn solid(col: Rgba) Self {
        return fromRgba8(1, 1, &col, .{ .filter = .nearest, .mipmaps = false, .repeat = false });
    }

    pub fn deinit(self: Self) void {
        gl.DeleteTextures(1, @ptrCast(&self.id));
    }

    fn fromSurface(loaded: *sdl.SDL_Surface, options: Options) !Self {
        defer sdl.SDL_DestroySurface(loaded);

        const surf = sdl.SDL_ConvertSurface(loaded, sdl.SDL_PIXELFORMAT_RGBA32) orelse {
            logSdlError();
            return error.ImageConvertFailed;
        };
        defer sdl.SDL_DestroySurface(surf);

        const w: usize = @intCast(surf.*.w);
        const h: usize = @intCast(surf.*.h);
        if (@as(usize, @intCast(surf.*.pitch)) != w * 4) return error.UnexpectedPitch;

        const bytes: [*]const u8 = @ptrCast(surf.*.pixels.?);
        return fromRgba8(@intCast(w), @intCast(h), bytes[0 .. w * h * 4], options);
    }
};

pub const Mesh = struct {
    vao: c_uint = 0,
    vbo: c_uint = 0,
    ibo: c_uint = 0,
    count: c_int = 0,
    indexed: bool = false,

    const NormalGen = enum {
        auto, // if every vertex provides a normal then use normals, else use compute smooth
        provided, // uses provided normals
        smooth, // average face normals at shared vertices (needs indices)
        flat, // one normal per triangle (duplicates vertices)
    };

    pub const Options = struct {
        normal_gen: NormalGen = .auto,
    };

    const Self = @This();

    pub fn init(allocator: mem.Allocator, vertices: []const Vertex, indices: ?[]const u32, options: Options) !Self {
        var mode = options.normal_gen;
        if (mode == .auto) {
            mode = .provided;
            for (vertices) |v| {
                if (!hasNormal(v.normal)) {
                    mode = .smooth;
                    break;
                }
            }
        }

        if (mode == .smooth and indices == null) mode = .flat;

        switch (mode) {
            .auto, .provided => return upload(vertices, indices),
            .smooth => {
                const copy = try allocator.dupe(Vertex, vertices);
                defer allocator.free(copy);
                computeSmooth(copy, indices.?);
                return upload(copy, indices);
            },
            .flat => {
                const count = if (indices) |idx| idx.len else vertices.len;
                const out = try allocator.alloc(Vertex, count);
                defer allocator.free(out);
                for (0..count) |i| {
                    out[i] = vertices[if (indices) |idx| idx[i] else i];
                }
                var t: usize = 0;
                while (t + 2 < count) : (t += 3) {
                    const n = normalize(cross(
                        sub(out[t + 1].pos, out[t].pos),
                        sub(out[t + 2].pos, out[t].pos),
                    ));
                    out[t].normal = n;
                    out[t + 1].normal = n;
                    out[t + 2].normal = n;
                }
                return upload(out, null);
            },
        }
    }

    pub fn deinit(self: *Self) void {
        if (self.ibo != 0) gl.DeleteBuffers(1, @ptrCast(&self.ibo));
        if (self.vbo != 0) gl.DeleteBuffers(1, @ptrCast(&self.vbo));
        if (self.vao != 0) gl.DeleteVertexArrays(1, @ptrCast(&self.vao));
        self.* = .{};
    }

    fn upload(vertices: []const Vertex, indices: ?[]const u32) Self {
        var m: Self = .{};

        gl.GenVertexArrays(1, @ptrCast(&m.vao));
        gl.GenBuffers(1, @ptrCast(&m.vbo));
        gl.BindVertexArray(m.vao);

        gl.BindBuffer(gl.ARRAY_BUFFER, m.vbo);
        gl.BufferData(
            gl.ARRAY_BUFFER,
            @intCast(vertices.len * @sizeOf(Vertex)),
            vertices.ptr,
            gl.STATIC_DRAW,
        );

        if (indices) |idx| {
            m.indexed = true;
            m.count = @intCast(idx.len);
            gl.GenBuffers(1, @ptrCast(&m.ibo));
            gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, m.ibo);
            gl.BufferData(
                gl.ELEMENT_ARRAY_BUFFER,
                @intCast(idx.len * @sizeOf(u32)),
                idx.ptr,
                gl.STATIC_DRAW,
            );
        } else {
            m.indexed = false;
            m.count = @intCast(vertices.len);
        }

        const stride = @sizeOf(Vertex);
        gl.EnableVertexAttribArray(0);
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, stride, @offsetOf(Vertex, "pos"));

        gl.EnableVertexAttribArray(1);
        gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, stride, @offsetOf(Vertex, "uv"));

        gl.EnableVertexAttribArray(2);
        gl.VertexAttribPointer(2, 3, gl.FLOAT, gl.FALSE, stride, @offsetOf(Vertex, "normal"));

        gl.BindVertexArray(0);

        return m;
    }

    fn computeSmooth(v: []Vertex, idx: []const u32) void {
        for (v) |*x| x.normal = .{ 0, 0, 0 };

        var t: usize = 0;
        while (t + 2 < idx.len) : (t += 3) {
            const tri = [3]u32{ idx[t], idx[t + 1], idx[t + 2] };
            const n = cross(
                sub(v[tri[1]].pos, v[tri[0]].pos),
                sub(v[tri[2]].pos, v[tri[0]].pos),
            );
            for (tri) |i| {
                v[i].normal[0] += n[0];
                v[i].normal[1] += n[1];
                v[i].normal[2] += n[2];
            }
        }
        for (v) |*x| x.normal = normalize(x.normal);
    }
};

pub const Shader = struct {
    program: c_uint,

    const Self = @This();

    pub fn init(allocator: mem.Allocator, vertex_srcs: []const []const u8, fragment_srcs: []const []const u8) !Self {
        if (vertex_srcs.len == 0 or fragment_srcs.len == 0) return error.MissingShaderSources;

        const program = gl.CreateProgram();
        errdefer gl.DeleteProgram(program);

        for (vertex_srcs) |src| {
            const vertex_shader = try compile(allocator, gl.VERTEX_SHADER, src);
            defer gl.DeleteShader(vertex_shader);

            gl.AttachShader(program, vertex_shader);
        }
        for (fragment_srcs) |src| {
            const fragment_shader = try compile(allocator, gl.FRAGMENT_SHADER, src);
            defer gl.DeleteShader(fragment_shader);

            gl.AttachShader(program, fragment_shader);
        }

        gl.LinkProgram(program);

        var status: [1]i32 = undefined;
        gl.GetProgramiv(program, gl.LINK_STATUS, &status);
        if (status[0] == gl.FALSE) {
            logProgramInfo(allocator, program);
            return error.ProgramLinkFailed;
        }
        return .{ .program = program };
    }

    pub fn use(self: Self) void {
        gl.UseProgram(self.program);
    }

    pub fn deinit(self: Self) void {
        gl.DeleteProgram(self.program);
    }

    pub fn loc(self: Self, name: [:0]const u8) c_int {
        return gl.GetUniformLocation(self.program, name.ptr);
    }

    fn compile(allocator: mem.Allocator, kind: c_uint, src: []const u8) !c_uint {
        const shader = gl.CreateShader(kind);
        errdefer gl.DeleteShader(shader);

        const ptr: [*c]const u8 = src.ptr;
        const len: c_uint = @intCast(src.len);
        gl.ShaderSource(shader, 1, @ptrCast(&ptr), @ptrCast(&len));
        gl.CompileShader(shader);

        var status: [1]i32 = undefined;
        gl.GetShaderiv(shader, gl.COMPILE_STATUS, &status);

        if (status[0] == gl.FALSE) {
            logShaderInfo(allocator, shader);
            return error.ShaderCompileFailed;
        }
        return shader;
    }

    fn logShaderInfo(allocator: mem.Allocator, shader: c_uint) void {
        var log_len: [1]i32 = .{0};
        gl.GetShaderiv(shader, gl.INFO_LOG_LENGTH, &log_len);

        if (log_len[0] <= 1) return;

        const buf = allocator.alloc(u8, @intCast(log_len[0])) catch return;
        defer allocator.free(buf);

        gl.GetShaderInfoLog(shader, @intCast(buf.len), null, buf.ptr);
        log.err("Shader compile error:\n{s}", .{buf});
    }

    fn logProgramInfo(allocator: mem.Allocator, program: c_uint) void {
        var log_len: [1]i32 = .{0};
        gl.GetProgramiv(program, gl.INFO_LOG_LENGTH, &log_len);

        if (log_len[0] <= 1) return;

        const buf = allocator.alloc(u8, @intCast(log_len[0])) catch return;
        defer allocator.free(buf);

        gl.GetProgramInfoLog(program, @intCast(buf.len), null, buf.ptr);
        log.err("Program link error:\n{s}", .{buf});
    }
};

pub const Renderer = struct {
    allocator: mem.Allocator,
    window: *sdl.SDL_Window,
    ctx: sdl.SDL_GLContext,
    procs: gl.ProcTable,

    clear_color: [4]f32,

    pub const AntiAliasing = union(enum) {
        none: void,
        msaa: struct {
            samples: c_int = 4,
            sample_shading: bool = false,
            min_sample_shading: f32 = 1.0,
        },
    };

    pub const InitOptions = struct {
        title: [:0]const u8 = "game",
        width: c_int = 1280,
        height: c_int = 720,
        flags: u64 = sdl.SDL_WINDOW_FULLSCREEN | sdl.SDL_WINDOW_BORDERLESS,
        vsync: bool = true,
        depth_test: bool = true,
        cull_backface: bool = true,
        anti_aliasing: AntiAliasing = .{ .msaa = .{} },
    };

    const Self = @This();

    const loc = struct {
        const model = 0;
        const view_proj = 1;
        const texture = 2;
    };

    pub fn init(allocator: mem.Allocator, options: InitOptions) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        self.allocator = allocator;
        self.clear_color = .{ 0.0, 0.0, 0.0, 1.0 };

        if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
            logSdlError();
            return error.SdlInitFailed;
        }
        errdefer sdl.SDL_Quit();

        _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, 4);
        _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MINOR_VERSION, 3);
        _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_CORE);
        _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DEPTH_SIZE, 24);

        if (options.anti_aliasing == .msaa) {
            _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_MULTISAMPLEBUFFERS, 1);
            _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_MULTISAMPLESAMPLES, options.anti_aliasing.msaa.samples);
        }

        self.window = sdl.SDL_CreateWindow(
            options.title,
            options.width,
            options.height,
            options.flags | sdl.SDL_WINDOW_OPENGL,
        ) orelse {
            logSdlError();
            return error.WindowCreateFailed;
        };
        errdefer sdl.SDL_DestroyWindow(self.window);

        self.ctx = sdl.SDL_GL_CreateContext(self.window) orelse {
            logSdlError();
            return error.GlContextFailed;
        };
        errdefer _ = sdl.SDL_GL_DestroyContext(self.ctx);

        _ = sdl.SDL_GL_SetSwapInterval(@intFromBool(options.vsync));

        if (!self.procs.init(glProcLoader)) return error.GlLoadFailed;
        gl.makeProcTableCurrent(&self.procs);

        if (options.depth_test) gl.Enable(gl.DEPTH_TEST);
        if (options.anti_aliasing == .msaa) {
            gl.Enable(gl.MULTISAMPLE);
            if (options.anti_aliasing.msaa.sample_shading) {
                gl.Enable(gl.SAMPLE_SHADING);
                gl.MinSampleShading(options.anti_aliasing.msaa.min_sample_shading);
            }
        }
        if (options.cull_backface) {
            gl.Enable(gl.CULL_FACE);
            gl.CullFace(gl.BACK);
            gl.FrontFace(gl.CCW);
        }
        gl.Enable(gl.BLEND);
        gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        return self;
    }

    pub fn deinit(self: *Self) void {
        _ = sdl.SDL_GL_DestroyContext(self.ctx);
        sdl.SDL_DestroyWindow(self.window);
        sdl.SDL_Quit();
        self.allocator.destroy(self);
    }

    pub fn pollEvents(self: *Self) bool {
        _ = self;
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event)) {
            switch (event.type) {
                sdl.SDL_EVENT_QUIT => return false,
                else => {},
            }
        }
        return true;
    }

    pub fn time(self: *Self) f32 {
        _ = self;
        return @as(f32, @floatFromInt(sdl.SDL_GetTicks())) / 1000.0;
    }

    pub fn size(self: *Self) [2]i32 {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = sdl.SDL_GetWindowSizeInPixels(self.window, &w, &h);
        return .{ w, @max(h, 1) };
    }

    pub fn beginFrame(self: *Self, view_proj: Mat4) void {
        const s = self.size();
        gl.Viewport(0, 0, s[0], s[1]);
        gl.ClearColor(self.clear_color[0], self.clear_color[1], self.clear_color[2], self.clear_color[3]);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        gl.UniformMatrix4fv(loc.view_proj, 1, gl.FALSE, @ptrCast(&view_proj));
        gl.Uniform1i(loc.texture, 0);
    }

    pub fn endFrame(self: *Self) void {
        _ = sdl.SDL_GL_SwapWindow(self.window);
    }

    pub fn drawMesh(self: *Self, mesh: Mesh, model: Mat4, texture: Texture, program: Shader) void {
        _ = self;
        if (mesh.count == 0) return;

        program.use();

        gl.ActiveTexture(gl.TEXTURE0);
        gl.BindTexture(gl.TEXTURE_2D, texture.id);
        gl.UniformMatrix4fv(loc.model, 1, gl.FALSE, @ptrCast(&model));

        gl.BindVertexArray(mesh.vao);
        if (mesh.indexed) {
            gl.DrawElements(gl.TRIANGLES, mesh.count, gl.UNSIGNED_INT, 0);
        } else {
            gl.DrawArrays(gl.TRIANGLES, 0, mesh.count);
        }
    }

    pub fn drawMeshes(self: *Self, mesh: Mesh, models: []const Mat4, texture: Texture, program: Shader) void {
        _ = self;
        if (mesh.count == 0) return;

        program.use();

        gl.ActiveTexture(gl.TEXTURE0);
        gl.BindTexture(gl.TEXTURE_2D, texture.id);
        gl.BindVertexArray(mesh.vao);

        for (models) |model| {
            gl.UniformMatrix4fv(loc.model, 1, gl.FALSE, @ptrCast(&model));
            if (mesh.indexed) {
                gl.DrawElements(gl.TRIANGLES, mesh.count, gl.UNSIGNED_INT, 0);
            } else {
                gl.DrawArrays(gl.TRIANGLES, 0, mesh.count);
            }
        }
    }

    fn glProcLoader(name: [*:0]const u8) ?gl.PROC {
        const p = sdl.SDL_GL_GetProcAddress(name);
        if (p == null) log.err("missing GL proc: {s}", .{name});
        return @ptrCast(p);
    }
};
