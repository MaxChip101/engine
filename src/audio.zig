const std = @import("std");
const mem = std.mem;
const atomic = std.atomic;
const log = std.log;

const sdl = @import("sdl3");

fn logSdlError() void {
    log.err("[SDL] error: {s}", .{sdl.SDL_GetError()});
}

pub const Callback = *const fn (
    ctx: ?*anyopaque,
    input: []const f32,
    output: []f32,
    config: Audio.Config,
) void;

pub const Sound = struct {
    samples: []f32,
    channels: u32,
    sample_rate: u32,

    pub const Options = struct {
        sample_rate: u32 = 44_100,
        channels: u32 = 2,
    };

    const Self = @This();

    pub fn fromF32(
        allocator: mem.Allocator,
        src_channels: u32,
        src_sample_rate: u32,
        samples: []const f32,
        options: Options,
    ) !Self {
        std.debug.assert(src_channels > 0 and samples.len % src_channels == 0);

        if (src_channels == options.channels and src_sample_rate == options.sample_rate) {
            return .{
                .samples = try allocator.dupe(f32, samples),
                .channels = options.channels,
                .sample_rate = options.sample_rate,
            };
        }

        const src_spec = sdl.SDL_AudioSpec{
            .format = sdl.SDL_AUDIO_F32,
            .channels = @intCast(src_channels),
            .freq = @intCast(src_sample_rate),
        };
        return fromBytes(allocator, src_spec, mem.sliceAsBytes(samples), options);
    }

    pub fn fromWav(allocator: mem.Allocator, data: []const u8, options: Options) !Self {
        const io = sdl.SDL_IOFromConstMem(data.ptr, data.len) orelse {
            logSdlError();
            return error.SoundLoadFailed;
        };

        var spec: sdl.SDL_AudioSpec = undefined;
        var buf: [*c]u8 = null;
        var len: u32 = 0;
        if (!sdl.SDL_LoadWAV_IO(io, true, &spec, &buf, &len)) {
            logSdlError();
            return error.SoundLoadFailed;
        }
        defer sdl.SDL_free(buf);

        return fromBytes(allocator, spec, buf[0..len], options);
    }

    pub fn silence(allocator: mem.Allocator, seconds: f32, options: Options) !Self {
        const frame_count: usize = @intFromFloat(seconds * @as(f32, @floatFromInt(options.sample_rate)));
        const samples = try allocator.alloc(f32, frame_count * options.channels);
        @memset(samples, 0);
        return .{
            .samples = samples,
            .channels = options.channels,
            .sample_rate = options.sample_rate,
        };
    }

    pub fn sine(allocator: mem.Allocator, freq: f32, seconds: f32, volume: f32, options: Options) !Self {
        const rate: f32 = @floatFromInt(options.sample_rate);
        const frame_count: usize = @intFromFloat(seconds * rate);
        const samples = try allocator.alloc(f32, frame_count * options.channels);

        const step: f64 = 2.0 * std.math.pi * @as(f64, freq) / rate;
        for (0..frame_count) |i| {
            const v = volume * @as(f32, @floatCast(@sin(step * @as(f64, @floatFromInt(i)))));
            for (0..options.channels) |c| samples[i * options.channels + c] = v;
        }

        return .{
            .samples = samples,
            .channels = options.channels,
            .sample_rate = options.sample_rate,
        };
    }

    pub fn square(allocator: mem.Allocator, freq: f32, seconds: f32, volume: f32, options: Options) !Self {
        const rate: f32 = @floatFromInt(options.sample_rate);
        const frame_count: usize = @intFromFloat(seconds * rate);
        const samples = try allocator.alloc(f32, frame_count * options.channels);

        const step: f64 = @as(f64, freq) / rate;
        for (0..frame_count) |i| {
            const phase = @mod(@as(f64, @floatFromInt(i)) * step, 1.0);
            const wave: f32 = if (phase < 0.5) 1.0 else -1.0;
            const v = volume * wave;
            for (0..options.channels) |c| samples[i * options.channels + c] = v;
        }

        return .{
            .samples = samples,
            .channels = options.channels,
            .sample_rate = options.sample_rate,
        };
    }

    pub fn saw(allocator: mem.Allocator, freq: f32, seconds: f32, volume: f32, options: Options) !Self {
        const rate: f32 = @floatFromInt(options.sample_rate);
        const frame_count: usize = @intFromFloat(seconds * rate);
        const samples = try allocator.alloc(f32, frame_count * options.channels);

        const step: f64 = @as(f64, freq) / rate;
        for (0..frame_count) |i| {
            const phase = @mod(@as(f64, @floatFromInt(i)) * step, 1.0);
            const wave: f32 = @floatCast(2.0 * phase - 1.0);
            const v = volume * wave;
            for (0..options.channels) |c| samples[i * options.channels + c] = v;
        }

        return .{
            .samples = samples,
            .channels = options.channels,
            .sample_rate = options.sample_rate,
        };
    }

    pub fn triangle(allocator: mem.Allocator, freq: f32, seconds: f32, volume: f32, options: Options) !Self {
        const rate: f32 = @floatFromInt(options.sample_rate);
        const frame_count: usize = @intFromFloat(seconds * rate);
        const samples = try allocator.alloc(f32, frame_count * options.channels);

        const step: f64 = @as(f64, freq) / rate;
        for (0..frame_count) |i| {
            const phase = @mod(@as(f64, @floatFromInt(i)) * step, 1.0);
            const wave: f32 = @floatCast(4.0 * @abs(phase - 0.5) - 1.0);
            const v = volume * wave;
            for (0..options.channels) |c| samples[i * options.channels + c] = v;
        }

        return .{
            .samples = samples,
            .channels = options.channels,
            .sample_rate = options.sample_rate,
        };
    }

    pub fn frames(self: Self) usize {
        return self.samples.len / self.channels;
    }

    pub fn durationSeconds(self: Self) f32 {
        return @as(f32, @floatFromInt(self.frames())) / @as(f32, @floatFromInt(self.sample_rate));
    }

    pub fn deinit(self: Self, allocator: mem.Allocator) void {
        allocator.free(self.samples);
    }

    fn fromBytes(
        allocator: mem.Allocator,
        src_spec: sdl.SDL_AudioSpec,
        data: []const u8,
        options: Options,
    ) !Self {
        const dst_spec = sdl.SDL_AudioSpec{
            .format = sdl.SDL_AUDIO_F32,
            .channels = @intCast(options.channels),
            .freq = @intCast(options.sample_rate),
        };

        var out_ptr: [*c]u8 = null;
        var out_len: c_int = 0;
        if (!sdl.SDL_ConvertAudioSamples(&src_spec, data.ptr, @intCast(data.len), &dst_spec, &out_ptr, &out_len)) {
            logSdlError();
            return error.SoundConvertFailed;
        }
        defer sdl.SDL_free(out_ptr);

        const count = @as(usize, @intCast(out_len)) / @sizeOf(f32);
        const samples = try allocator.alloc(f32, count);
        @memcpy(mem.sliceAsBytes(samples), out_ptr[0 .. count * @sizeOf(f32)]);

        return .{
            .samples = samples,
            .channels = options.channels,
            .sample_rate = options.sample_rate,
        };
    }
};

pub const Audio = struct {
    allocator: mem.Allocator,
    config: Config,
    callback: Callback,
    ctx: ?*anyopaque,
    out_scratch: []f32,
    in_scratch: []f32,
    playback: *sdl.SDL_AudioStream,
    recording: ?*sdl.SDL_AudioStream = null,
    dropped: atomic.Value(u32) = .init(0),

    const Self = @This();

    pub const Config = struct {
        sample_rate: u32 = 44_100,
        buffer_frames: u32 = 512,
        in_channels: u32 = 0,
        out_channels: u32 = 2,

        pub fn soundOptions(self: Config) Sound.Options {
            return .{
                .sample_rate = self.sample_rate,
                .channels = self.out_channels,
            };
        }
    };

    pub fn init(allocator: mem.Allocator, config: Config, callback: Callback, ctx: ?*anyopaque) !*Self {
        if (config.out_channels == 0 or config.buffer_frames == 0) return error.InvalidConfig;

        if (!sdl.SDL_Init(sdl.SDL_INIT_AUDIO)) {
            logSdlError();
            return error.SdlInitFailed;
        }
        errdefer sdl.SDL_QuitSubSystem(sdl.SDL_INIT_AUDIO);

        var hint_buf: [16]u8 = undefined;
        const hint = std.fmt.bufPrintZ(&hint_buf, "{d}", .{config.buffer_frames}) catch unreachable;
        _ = sdl.SDL_SetHint(sdl.SDL_HINT_AUDIO_DEVICE_SAMPLE_FRAMES, hint.ptr);

        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const out_scratch = try allocator.alloc(f32, config.buffer_frames * config.out_channels);
        errdefer allocator.free(out_scratch);
        const in_scratch = try allocator.alloc(f32, config.buffer_frames * config.in_channels);
        errdefer allocator.free(in_scratch);

        self.* = .{
            .allocator = allocator,
            .config = config,
            .callback = callback,
            .ctx = ctx,
            .out_scratch = out_scratch,
            .in_scratch = in_scratch,
            .playback = undefined,
        };

        const out_spec = outSpec(config);
        self.playback = sdl.SDL_OpenAudioDeviceStream(
            sdl.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK,
            &out_spec,
            playbackCallback,
            self,
        ) orelse {
            logSdlError();
            return error.OpenPlaybackFailed;
        };
        errdefer sdl.SDL_DestroyAudioStream(self.playback);

        if (config.in_channels > 0) {
            const in_spec = inSpec(config);
            self.recording = sdl.SDL_OpenAudioDeviceStream(
                sdl.SDL_AUDIO_DEVICE_DEFAULT_RECORDING,
                &in_spec,
                null,
                null,
            ) orelse {
                logSdlError();
                return error.OpenRecordingFailed;
            };
        }
        errdefer if (self.recording) |r| sdl.SDL_DestroyAudioStream(r);

        if (self.recording) |r| {
            if (!sdl.SDL_ResumeAudioStreamDevice(r)) return error.ResumeFailed;
        }

        if (!sdl.SDL_ResumeAudioStreamDevice(self.playback)) return error.ResumeFailed;
        return self;
    }

    pub fn deinit(self: *Self) void {
        sdl.SDL_DestroyAudioStream(self.playback);
        if (self.recording) |r| sdl.SDL_DestroyAudioStream(r);
        sdl.SDL_QuitSubSystem(sdl.SDL_INIT_AUDIO);
        self.allocator.free(self.out_scratch);
        self.allocator.free(self.in_scratch);
        self.allocator.destroy(self);
    }

    fn playbackCallback(
        userdata: ?*anyopaque,
        stream: ?*sdl.SDL_AudioStream,
        additional_amount: c_int,
        total_amount: c_int,
    ) callconv(.c) void {
        _ = total_amount;
        if (additional_amount <= 0) return;

        const a: *Self = @ptrCast(@alignCast(userdata.?));
        const out_ch = a.config.out_channels;
        const in_ch = a.config.in_channels;
        var frames_needed: usize = @as(usize, @intCast(additional_amount)) / (out_ch * @sizeOf(f32));

        while (frames_needed > 0) {
            const n = @min(frames_needed, a.config.buffer_frames);

            const out = a.out_scratch[0 .. n * out_ch];
            @memset(out, 0);

            var in: []const f32 = &.{};
            if (a.recording) |rec| {
                const max_queued: c_int = @intCast(a.config.buffer_frames * in_ch * @sizeOf(f32) * 3);
                if (sdl.SDL_GetAudioStreamAvailable(rec) > max_queued) {
                    _ = sdl.SDL_ClearAudioStream(rec);
                }
                const buf = a.in_scratch[0 .. n * in_ch];
                const bytes = mem.sliceAsBytes(buf);
                const got = sdl.SDL_GetAudioStreamData(rec, bytes.ptr, @intCast(bytes.len));
                const got_u: usize = if (got > 0) @intCast(got) else 0;
                @memset(bytes[got_u..], 0);
                in = buf;
            }

            a.callback(a.ctx, in, out, a.config);

            for (out) |*s| {
                s.* = if (std.math.isNan(s.*)) 0 else std.math.clamp(s.*, -1.0, 1.0);
            }

            const out_bytes = mem.sliceAsBytes(out);
            if (!sdl.SDL_PutAudioStreamData(stream, out_bytes.ptr, @intCast(out_bytes.len))) {
                _ = a.dropped.fetchAdd(1, .monotonic);
                return;
            }
            frames_needed -= n;
        }
    }
};

fn outSpec(config: Audio.Config) sdl.SDL_AudioSpec {
    return .{
        .format = sdl.SDL_AUDIO_F32,
        .channels = @intCast(config.out_channels),
        .freq = @intCast(config.sample_rate),
    };
}

fn inSpec(config: Audio.Config) sdl.SDL_AudioSpec {
    return .{
        .format = sdl.SDL_AUDIO_F32,
        .channels = @intCast(config.in_channels),
        .freq = @intCast(config.sample_rate),
    };
}
