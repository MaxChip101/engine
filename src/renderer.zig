const std = @import("std");
const mem = std.mem;
const log = std.log;

const sdl = @import("sdl3");
const gl = @import("gl");
const zm = @import("zmath");

const Window = @import("windows.zig").Window;

pub const Mat4 = [16]f32;
// might need later but not now
// pub const identity: Mat4 = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 };

pub const Rgba8 = [4]u8;

// helper functions for zmath
fn faceNormal(a: [3]f32, b: [3]f32, c: [3]f32) zm.Vec {
    const pa = zm.loadArr3(a);
    return zm.cross3(zm.loadArr3(b) - pa, zm.loadArr3(c) - pa);
}

fn safeNormalize3(v: zm.Vec) zm.Vec {
    if (zm.lengthSq3(v)[0] < 1e12) return .{ 0.0, 0.0, 1.0, 0.0 };
    return zm.normalize3(v);
}

fn logSdlError() void {
    log.err("[SDL] error: {s}", .{sdl.SDL_GetError()});
}

pub const Vertex = extern struct {
    pos: [3]f32,
    uv: [2]f32 = .{ 0.0, 0.0 },
    normal: [3]f32 = .{ 0.0, 0.0, 0.0 },
};

pub const Cubemap = struct {
    id: c_uint,
    size: u32,

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

    pub const faces = [_]c_uint{
        gl.TEXTURE_CUBE_MAP_POSITIVE_X,
        gl.TEXTURE_CUBE_MAP_NEGATIVE_X,
        gl.TEXTURE_CUBE_MAP_POSITIVE_Y,
        gl.TEXTURE_CUBE_MAP_NEGATIVE_Y,
        gl.TEXTURE_CUBE_MAP_POSITIVE_Z,
        gl.TEXTURE_CUBE_MAP_NEGATIVE_Z,
    };

    pub fn fromRgba8Faces(size: u32, face_pixels: [6][]const u8, options: Options) Self {
        var id: c_uint = 0;
        gl.GenTextures(1, @ptrCast(&id));
        gl.BindTexture(gl.TEXTURE_CUBE_MAP, id);

        gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1);
        for (faces, face_pixels) |target, pixels| {
            std.debug.assert(pixels.len == @as(usize, size) * size * 4);
            gl.TexImage2D(
                target,
                0,
                gl.RGBA8,
                @intCast(size),
                @intCast(size),
                0,
                gl.RGBA,
                gl.UNSIGNED_BYTE,
                pixels.ptr,
            );
        }

        const wrap: c_int = if (options.repeat) gl.REPEAT else gl.CLAMP_TO_EDGE;
        const mag: c_int = if (options.filter == .linear) gl.LINEAR else gl.NEAREST;
        const min: c_int = switch (options.filter) {
            .linear => if (options.mipmaps) gl.LINEAR_MIPMAP_LINEAR else gl.LINEAR,
            .nearest => if (options.mipmaps) gl.NEAREST_MIPMAP_NEAREST else gl.NEAREST,
        };
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, wrap);
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, wrap);
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, wrap);
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, min);
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, mag);
        if (options.mipmaps) gl.GenerateMipmap(gl.TEXTURE_CUBE_MAP);

        return .{
            .id = id,
            .size = size,
        };
    }

    pub fn fromRgba8Atlas(allocator: mem.Allocator, width: usize, height: usize, pixels: []const u8, uv_coords: [6][4]f32, options: Options) !Self {
        var size: ?usize = null;
        var px: [6][4]usize = undefined;
        for (uv_coords, 0..) |r, f| {
            const x0: usize = @intFromFloat(@round(r[0] * @as(f32, @floatFromInt(width))));
            const y0: usize = @intFromFloat(@round(r[1] * @as(f32, @floatFromInt(height))));
            const x1: usize = @intFromFloat(@round(r[2] * @as(f32, @floatFromInt(width))));
            const y1: usize = @intFromFloat(@round(r[3] * @as(f32, @floatFromInt(height))));

            if (x1 <= x0 or y1 <= y0 or x1 > width or y1 > height) return error.BadFaceRect;
            if (x1 - x0 != y1 - y0) return error.CubemapFaceIsNotSquare;
            if (size) |s| {
                if (s != x1 - x0) return error.CubemapFaceDoesNotMatch;
            } else size = x1 - x0;

            px[f] = .{ x0, y0, x1, y1 };
        }

        const sz = size.?;
        const face_bytes = sz * sz * 4;
        const buf = try allocator.alloc(u8, face_bytes * 6);
        defer allocator.free(buf);

        var slices: [6][]const u8 = undefined;
        for (px, 0..) |p, f| {
            for (0..sz) |y| {
                const s = ((p[1] + y) * width + p[0]) * 4;
                const d = f * face_bytes + y * sz * 4;
                @memcpy(buf[d..][0 .. sz * 4], pixels[s..][0 .. sz * 4]);
            }
            slices[f] = buf[f * face_bytes ..][0..face_bytes];
        }
        return fromRgba8Faces(@intCast(sz), slices, options);
    }

    pub fn fromBmpAtlas(allocator: mem.Allocator, data: []const u8, uv_coords: [6][4]f32, options: Options) !Self {
        const io = sdl.SDL_IOFromConstMem(data.ptr, data.len) orelse {
            logSdlError();
            return error.ImageLoadFailed;
        };

        const loaded = sdl.SDL_LoadBMP_IO(io, true) orelse {
            logSdlError();
            return error.ImageLoadFailed;
        };
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

        return fromRgba8Atlas(allocator, w, h, bytes[0 .. w * h * 4], uv_coords, options);
    }

    pub fn fromPngAtlas(allocator: mem.Allocator, data: []const u8, uv_coords: [6][4]f32, options: Options) !Self {
        const io = sdl.SDL_IOFromConstMem(data.ptr, data.len) orelse {
            logSdlError();
            return error.ImageLoadFailed;
        };

        const loaded = sdl.SDL_LoadPNG_IO(io, true) orelse {
            logSdlError();
            return error.ImageLoadFailed;
        };
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

        return fromRgba8Atlas(allocator, w, h, bytes[0 .. w * h * 4], uv_coords, options);
    }

    pub fn fromBmpFaces(data: [6][]const u8, options: Options) !Self {
        var loaded: [6]*sdl.SDL_Surface = undefined;
        var count: usize = 0;

        errdefer {
            for (loaded[0..count]) |surf| sdl.SDL_DestroySurface(surf);
        }

        for (0..6) |f| {
            const io = sdl.SDL_IOFromConstMem(data[f].ptr, data[f].len) orelse {
                logSdlError();
                return error.ImageLoadFailed;
            };
            loaded[f] = sdl.SDL_LoadBMP_IO(io, true) orelse {
                logSdlError();
                return error.ImageLoadFailed;
            };
            count += 1;
        }

        count = 0;
        return fromSurfaces(loaded, options);
    }

    pub fn fromPngFaces(data: [6][]const u8, options: Options) !Self {
        var loaded: [6]*sdl.SDL_Surface = undefined;
        var count: usize = 0;

        errdefer {
            for (loaded[0..count]) |surf| sdl.SDL_DestroySurface(surf);
        }

        for (0..6) |f| {
            const io = sdl.SDL_IOFromConstMem(data[f].ptr, data[f].len) orelse {
                logSdlError();
                return error.ImageLoadFailed;
            };
            loaded[f] = sdl.SDL_LoadPNG_IO(io, true) orelse {
                logSdlError();
                return error.ImageLoadFailed;
            };

            count += 1;
        }

        count = 0;
        return fromSurfaces(loaded, options);
    }

    pub fn checkerboard(comptime cells: usize, on_col: Rgba8, off_col: Rgba8) Self {
        const dim = cells * cells;
        var px: [6][dim * dim * 4]u8 = undefined;
        var slices: [6][]const u8 = undefined;

        for (0..6) |f| {
            for (0..dim) |y| {
                for (0..dim) |x| {
                    const on = ((x / cells) + (y / cells)) % 2 == 0;
                    const i = (y * dim + x) * 4;
                    px[f][i..][0..4].* = if (on) on_col else off_col;
                }
            }
            slices[f] = &px[f];
        }
        return fromRgba8Faces(@intCast(dim), slices, .{
            .filter = .nearest,
            .mipmaps = false,
            .repeat = false,
        });
    }

    pub fn solidFaces(cols: [6]Rgba8) Self {
        var slices: [6][]const u8 = undefined;
        for (0..6) |f| slices[f] = &cols[f];
        return fromRgba8Faces(1, slices, .{
            .filter = .nearest,
            .mipmaps = false,
            .repeat = false,
        });
    }

    pub fn solid(col: Rgba8) Self {
        return solidFaces(.{ col, col, col, col, col, col });
    }

    pub fn deinit(self: Self) void {
        gl.DeleteTextures(1, @ptrCast(&self.id));
    }

    fn fromSurfaces(allocator: mem.Allocator, loaded: [6]*sdl.SDL_Surface, options: Options) !Self {
        defer {
            for (loaded) |raw| sdl.SDL_DestroySurface(raw);
        }

        var buffers: [6][]u8 = undefined;
        var slices: [6][]const u8 = undefined;
        var allocated: usize = 0;

        errdefer {
            for (buffers[0..allocated]) |buf| allocator.free(buf);
        }

        var expected_size: ?usize = null;

        for (0..6) |f| {
            const surf = sdl.SDL_ConvertSurface(loaded[f], sdl.SDL_PIXELFORMAT_RGBA32) orelse {
                logSdlError();
                return error.ImageConvertFailed;
            };
            defer sdl.SDL_DestroySurface(surf);

            const w: usize = @intCast(surf.*.w);
            const h: usize = @intCast(surf.*.h);
            if (@as(usize, @intCast(surf.*.pitch)) != w * 4) return error.UnexpectedPitch;
            if (w != h) return error.CubemapFaceIsNotSquare;

            if (expected_size) |s| {
                if (s != w) return error.CubemapFaceDoesNotMatch;
            } else {
                expected_size = w;
            }

            const byte_len = w * h * 4;
            const copy = try allocator.alloc(u8, byte_len);
            const src_ptr: [*]const u8 = @ptrCast(surf.*.pixels.?);
            @memcpy(copy, src_ptr[0..byte_len]);

            buffers[f] = copy;
            slices[f] = copy;
            allocated += 1;
        }

        const cubemap = fromRgba8Faces(@intCast(expected_size.?), slices, options);

        for (buffers[0..allocated]) |buf| allocator.free(buf);

        return cubemap;
    }
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
        gl.TexImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RGBA8,
            @intCast(width),
            @intCast(height),
            0,
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            pixels.ptr,
        );

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
        defer sdl.SDL_DestroySurface(loaded);

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
        defer sdl.SDL_DestroySurface(loaded);

        return fromSurface(loaded, options);
    }

    pub fn checkerboard(comptime cells: usize, on_col: Rgba8, off_col: Rgba8) Self {
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

    pub fn solid(col: Rgba8) Self {
        return fromRgba8(1, 1, &col, .{ .filter = .nearest, .mipmaps = false, .repeat = false });
    }

    pub fn deinit(self: Self) void {
        gl.DeleteTextures(1, @ptrCast(&self.id));
    }

    fn fromSurface(loaded: *sdl.SDL_Surface, options: Options) !Self {
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
                if (zm.lengthSq3(zm.loadArr3(v.normal))[0] == 0.0) {
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
                    const n = safeNormalize3(faceNormal(out[t].pos, out[t + 1].pos, out[t + 2].pos));
                    zm.storeArr3(&out[t].normal, n);
                    zm.storeArr3(&out[t + 1].normal, n);
                    zm.storeArr3(&out[t + 2].normal, n);
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
            const n = faceNormal(v[tri[0]].pos, v[tri[1]].pos, v[tri[2]].pos);
            for (tri) |i| {
                zm.storeArr3(&v[i].normal, zm.loadArr3(v[i].normal) + n);
            }
        }
        for (v) |*x| {
            zm.storeArr3(&x.normal, safeNormalize3(zm.loadArr3(x.normal)));
        }
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

    pub fn set(self: Self, name: [:0]const u8, value: anytype) void {
        const l = self.loc(name);
        if (l < 0) return;

        switch (@TypeOf(value)) {
            f32, comptime_float => gl.ProgramUniform1f(self.program, l, value),
            i32, comptime_int => gl.ProgramUniform1i(self.program, l, value),
            bool => gl.ProgramUniform1i(self.program, l, @intFromBool(value)),
            [2]f32 => gl.ProgramUniform2fv(self.program, l, 1, @ptrCast(&value)),
            [3]f32 => gl.ProgramUniform3fv(self.program, l, 1, @ptrCast(&value)),
            [4]f32 => gl.ProgramUniform4fv(self.program, l, 1, @ptrCast(&value)),
            [16]f32 => gl.ProgramUniformMatrix4fv(self.program, l, 1, gl.FALSE, @ptrCast(&value)),
            else => @compileError("unsupported uniform type: " ++ @typeName(@TypeOf(value))),
        }
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
    procs: gl.ProcTable,

    clear_color: [4]f32,

    pub const DepthFunc = enum(c_uint) {
        Never = gl.NEVER,
        Less = gl.LESS,
        Equal = gl.EQUAL,
        LessEqual = gl.LEQUAL,
        Greater = gl.GREATER,
        NotEqual = gl.NOTEQUAL,
        GreaterEqual = gl.GEQUAL,
        Always = gl.ALWAYS,
    };

    pub const AntiAliasing = union(enum) {
        none: void,
        msaa: struct {
            sample_shading: bool = false,
            min_sample_shading: f32 = 1.0,
        },
    };

    pub const InitOptions = struct {
        depth_test: bool = true, // make into a func set depth state
        cull_backface: bool = true, // per draw call
        anti_aliasing: AntiAliasing = .{ .msaa = .{} },
        clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 }, // already changable just need public functions dedicated for it
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
        self.clear_color = options.clear_color;

        if (!self.procs.init(glProcLoader)) return error.GlLoadFailed;
        gl.makeProcTableCurrent(&self.procs);

        if (options.depth_test) gl.Enable(gl.DEPTH_TEST); // per draw call
        if (options.anti_aliasing == .msaa) {
            gl.Enable(gl.MULTISAMPLE);
            if (options.anti_aliasing.msaa.sample_shading) {
                gl.Enable(gl.SAMPLE_SHADING);
                gl.MinSampleShading(options.anti_aliasing.msaa.min_sample_shading);
            }
        }
        if (options.cull_backface) { // per draw call
            gl.Enable(gl.CULL_FACE);
            gl.CullFace(gl.BACK);
            gl.FrontFace(gl.CCW);
        }
        gl.Enable(gl.BLEND); // per draw call
        gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA); // same with with this from above
        gl.Enable(gl.TEXTURE_CUBE_MAP_SEAMLESS);

        return self;
    }

    pub fn deinit(self: *Self) void {
        gl.makeProcTableCurrent(null);
        self.allocator.destroy(self);
    }

    pub fn setDepthFunc(_: *Self, func: DepthFunc) void {
        gl.DepthFunc(@intFromEnum(func));
    }

    pub fn beginFrame(self: *Self, window: *Window) void {
        window.makeCurrent();

        const s = window.size();
        gl.Viewport(0, 0, s[0], s[1]);
        gl.ClearColor(self.clear_color[0], self.clear_color[1], self.clear_color[2], self.clear_color[3]);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    }

    pub fn drawMesh(_: *Self, view_proj: Mat4, mesh: Mesh, model: Mat4, texture: Texture, program: Shader) void {
        if (mesh.count == 0) return;

        program.use();

        gl.UniformMatrix4fv(loc.view_proj, 1, gl.FALSE, @ptrCast(&view_proj));
        gl.Uniform1i(loc.texture, 0);

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

    pub fn drawMeshes(_: *Self, view_proj: Mat4, mesh: Mesh, models: []const Mat4, texture: Texture, program: Shader) void {
        if (mesh.count == 0) return;

        program.use();

        gl.UniformMatrix4fv(loc.view_proj, 1, gl.FALSE, @ptrCast(&view_proj));
        gl.Uniform1i(loc.texture, 0);

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

    pub fn drawCubemap(_: *Self, view_proj: Mat4, mesh: Mesh, model: Mat4, cubemap: Cubemap, program: Shader) void {
        if (mesh.count == 0) return;

        program.use();

        gl.UniformMatrix4fv(loc.view_proj, 1, gl.FALSE, @ptrCast(&view_proj));
        gl.Uniform1i(loc.texture, 0);

        gl.ActiveTexture(gl.TEXTURE0);
        gl.BindTexture(gl.TEXTURE_CUBE_MAP, cubemap.id);
        gl.UniformMatrix4fv(loc.model, 1, gl.FALSE, @ptrCast(&model));

        gl.BindVertexArray(mesh.vao);
        if (mesh.indexed) {
            gl.DrawElements(gl.TRIANGLES, mesh.count, gl.UNSIGNED_INT, 0);
        } else {
            gl.DrawArrays(gl.TRIANGLES, 0, mesh.count);
        }
    }

    pub fn drawCubemaps(_: *Self, view_proj: Mat4, mesh: Mesh, models: []const Mat4, cubemap: Cubemap, program: Shader) void {
        if (mesh.count == 0) return;

        program.use();

        gl.UniformMatrix4fv(loc.view_proj, 1, gl.FALSE, @ptrCast(&view_proj));
        gl.Uniform1i(loc.texture, 0);

        gl.ActiveTexture(gl.TEXTURE0);
        gl.BindTexture(gl.TEXTURE_CUBE_MAP, cubemap.id);

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
