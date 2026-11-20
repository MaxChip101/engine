const std = @import("std");
const mem = std.mem;
const log = std.log;

const input = @import("input.zig");

const sdl = @import("sdl3");
const gl = @import("gl");

fn logSdlError() void {
    log.err("[SDL] error: {s}", .{sdl.SDL_GetError()});
}

pub const Window = struct {
    allocator: mem.Allocator,
    handle: *sdl.SDL_Window,
    ctx: sdl.SDL_GLContext,

    input: input.Input,

    pub const AntiAliasing = union(enum) {
        none: void,
        msaa: struct {
            samples: c_int = 4,
        },
    };

    pub const InitOptions = struct {
        title: [:0]const u8 = "game",
        width: c_int = 1280,
        height: c_int = 720,
        flags: u64 = sdl.SDL_WINDOW_FULLSCREEN | sdl.SDL_WINDOW_BORDERLESS,
        vsync: bool = true,
        anti_aliasing: AntiAliasing = .{ .msaa = .{} },
    };

    const Self = @This();

    pub fn init(allocator: mem.Allocator, options: InitOptions) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.allocator = allocator;
        self.input = .{};

        if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
            logSdlError();
            return error.SdlInitFailed;
        }
        errdefer sdl.SDL_QuitSubSystem(sdl.SDL_INIT_VIDEO);

        _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, 4);
        _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MINOR_VERSION, 3);
        _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_CORE);
        _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DEPTH_SIZE, 24);

        if (options.anti_aliasing == .msaa) {
            _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_MULTISAMPLEBUFFERS, 1);
            _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_MULTISAMPLESAMPLES, options.anti_aliasing.msaa.samples);
        }

        self.handle = sdl.SDL_CreateWindow(
            options.title,
            options.width,
            options.height,
            options.flags | sdl.SDL_WINDOW_OPENGL,
        ) orelse {
            logSdlError();
            return error.WindowCreateFailed;
        };
        errdefer sdl.SDL_DestroyWindow(self.handle);

        self.ctx = sdl.SDL_GL_CreateContext(self.handle) orelse {
            logSdlError();
            return error.GlContextFailed;
        };
        errdefer _ = sdl.SDL_GL_DestroyContext(self.ctx);

        _ = sdl.SDL_GL_SetSwapInterval(@intFromBool(options.vsync));

        return self;
    }

    pub fn deinit(self: *Self) void {
        _ = sdl.SDL_GL_DestroyContext(self.ctx);
        sdl.SDL_DestroyWindow(self.handle);
        sdl.SDL_QuitSubSystem(sdl.SDL_INIT_VIDEO);
        self.allocator.destroy(self);
    }

    pub fn makeCurrent(self: *Self) void {
        if (!sdl.SDL_GL_MakeCurrent(self.handle, self.ctx)) {
            logSdlError();
        }
    }

    pub fn swap(self: *Self) void {
        _ = sdl.SDL_GL_SwapWindow(self.handle);
    }

    pub fn pollEvents(self: *Self) bool {
        self.input.beginFrame();

        var keep_running = true;
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event)) {
            self.input.handleEvent(event);
            if (event.type == sdl.SDL_EVENT_QUIT) {
                keep_running = false;
            }
        }
        return keep_running;
    }

    pub fn setRelativeMouse(self: *Self, enabled: bool) void {
        if (!sdl.SDL_SetWindowRelativeMouseMode(self.handle, enabled)) {
            logSdlError();
        }
    }

    pub fn relativeMouse(self: *const Self) bool {
        return sdl.SDL_GetWindowRelativeMouseMode(self.handle);
    }

    pub fn time(self: *Self) f32 {
        _ = self;
        return @as(f32, @floatFromInt(sdl.SDL_GetTicks())) / 1000.0;
    }

    pub fn size(self: *Self) [2]i32 {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = sdl.SDL_GetWindowSizeInPixels(self.handle, &w, &h);
        return .{ w, @max(h, 1) };
    }
};
