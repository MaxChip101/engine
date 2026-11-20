const std = @import("std");

const sdl = @import("sdl3");

const Button = enum(usize) {
    @"0",
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,

    Space,
    LeftShift,
    RightShift,
    Escape,
    LeftControl,
    RightControl,
    Tab,
    Return,
    BackSpace,
    LeftAlt,
    RightAlt,

    Left,
    Up,
    Down,
    Right,

    MouseLeft,
    MouseRight,
    MouseMiddle,

    pub fn fromScancode(code: sdl.SDL_Scancode) ?Button {
        return switch (code) {
            sdl.SDL_SCANCODE_0 => Button.@"0",
            sdl.SDL_SCANCODE_1 => Button.@"1",
            sdl.SDL_SCANCODE_2 => Button.@"2",
            sdl.SDL_SCANCODE_3 => Button.@"3",
            sdl.SDL_SCANCODE_4 => Button.@"4",
            sdl.SDL_SCANCODE_5 => Button.@"5",
            sdl.SDL_SCANCODE_6 => Button.@"6",
            sdl.SDL_SCANCODE_7 => Button.@"7",
            sdl.SDL_SCANCODE_8 => Button.@"8",
            sdl.SDL_SCANCODE_9 => Button.@"9",
            sdl.SDL_SCANCODE_A => Button.A,
            sdl.SDL_SCANCODE_B => Button.B,
            sdl.SDL_SCANCODE_C => Button.C,
            sdl.SDL_SCANCODE_D => Button.D,
            sdl.SDL_SCANCODE_E => Button.E,
            sdl.SDL_SCANCODE_F => Button.F,
            sdl.SDL_SCANCODE_G => Button.G,
            sdl.SDL_SCANCODE_H => Button.H,
            sdl.SDL_SCANCODE_I => Button.I,
            sdl.SDL_SCANCODE_J => Button.J,
            sdl.SDL_SCANCODE_K => Button.K,
            sdl.SDL_SCANCODE_L => Button.L,
            sdl.SDL_SCANCODE_M => Button.M,
            sdl.SDL_SCANCODE_N => Button.N,
            sdl.SDL_SCANCODE_O => Button.O,
            sdl.SDL_SCANCODE_P => Button.P,
            sdl.SDL_SCANCODE_Q => Button.Q,
            sdl.SDL_SCANCODE_R => Button.R,
            sdl.SDL_SCANCODE_S => Button.S,
            sdl.SDL_SCANCODE_T => Button.T,
            sdl.SDL_SCANCODE_U => Button.U,
            sdl.SDL_SCANCODE_V => Button.V,
            sdl.SDL_SCANCODE_W => Button.W,
            sdl.SDL_SCANCODE_X => Button.X,
            sdl.SDL_SCANCODE_Y => Button.Y,
            sdl.SDL_SCANCODE_Z => Button.Z,
            sdl.SDL_SCANCODE_SPACE => Button.Space,
            sdl.SDL_SCANCODE_LSHIFT => Button.LeftShift,
            sdl.SDL_SCANCODE_RSHIFT => Button.RightShift,
            sdl.SDL_SCANCODE_ESCAPE => Button.Escape,
            sdl.SDL_SCANCODE_LCTRL => Button.LeftControl,
            sdl.SDL_SCANCODE_RCTRL => Button.RightControl,
            sdl.SDL_SCANCODE_TAB => Button.Tab,
            sdl.SDL_SCANCODE_RETURN => Button.Return,
            sdl.SDL_SCANCODE_BACKSPACE => Button.BackSpace,
            sdl.SDL_SCANCODE_LALT => Button.LeftAlt,
            sdl.SDL_SCANCODE_RALT => Button.RightAlt,
            sdl.SDL_SCANCODE_LEFT => Button.Left,
            sdl.SDL_SCANCODE_UP => Button.Up,
            sdl.SDL_SCANCODE_DOWN => Button.Down,
            sdl.SDL_SCANCODE_RIGHT => Button.Right,
            else => null,
        };
    }

    pub fn fromMouseButton(btn: u8) ?Button {
        return switch (btn) {
            sdl.SDL_BUTTON_LEFT => .MouseLeft,
            sdl.SDL_BUTTON_RIGHT => .MouseRight,
            sdl.SDL_BUTTON_MIDDLE => .MouseMiddle,
            else => null,
        };
    }
};

const button_len = @typeInfo(Button).@"enum".fields.len;

pub const Input = struct {
    down: [button_len]bool = .{false} ** button_len,
    pressed: [button_len]bool = .{false} ** button_len,
    released: [button_len]bool = .{false} ** button_len,

    mouse_pos: [2]f32 = .{ 0.0, 0.0 },
    mouse_delta: [2]f32 = .{ 0.0, 0.0 },
    scroll: [2]f32 = .{ 0.0, 0.0 },
    // impl other inputs

    resized: ?[2]u32 = null,

    const Self = @This();

    pub fn beginFrame(self: *Input) void {
        self.pressed = .{false} ** button_len;
        self.released = .{false} ** button_len;
        self.mouse_delta = .{ 0.0, 0.0 };
        self.scroll = .{ 0.0, 0.0 };
        self.resized = null;
    }

    pub fn handleEvent(self: *Self, event: sdl.SDL_Event) void {
        switch (event.type) {
            sdl.SDL_EVENT_WINDOW_RESIZED => {
                self.resized = .{
                    @intCast(@max(0, event.window.data1)),
                    @intCast(@max(0, event.window.data2)),
                };
            },

            sdl.SDL_EVENT_KEY_DOWN => {
                if (!event.key.repeat) {
                    if (Button.fromScancode(event.key.scancode)) |b| self.pressButton(b);
                }
            },
            sdl.SDL_EVENT_KEY_UP => {
                if (!event.key.repeat) {
                    if (Button.fromScancode(event.key.scancode)) |b| self.releaseButton(b);
                }
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                if (Button.fromMouseButton(event.button.button)) |b| self.pressButton(b);
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_UP => {
                if (Button.fromMouseButton(event.button.button)) |b| self.releaseButton(b);
            },
            sdl.SDL_EVENT_MOUSE_MOTION => {
                self.mouse_pos = .{ event.motion.x, event.motion.y };
                self.mouse_delta[0] += event.motion.xrel;
                self.mouse_delta[1] += event.motion.yrel;
            },
            sdl.SDL_EVENT_MOUSE_WHEEL => {
                self.scroll[0] += event.wheel.x;
                self.scroll[1] += event.wheel.y;
            },

            else => {},
        }
    }

    fn pressButton(self: *Input, b: Button) void {
        const idx = @intFromEnum(b);
        if (!self.down[idx]) self.pressed[idx] = true;
        self.down[idx] = true;
    }

    fn releaseButton(self: *Input, b: Button) void {
        const idx = @intFromEnum(b);
        if (self.down[idx]) self.released[idx] = true;
        self.down[idx] = false;
    }

    pub fn isDown(self: Input, b: Button) bool {
        return self.down[@intFromEnum(b)];
    }

    pub fn isPressed(self: Input, b: Button) bool {
        return self.pressed[@intFromEnum(b)];
    }

    pub fn isReleased(self: Input, b: Button) bool {
        return self.released[@intFromEnum(b)];
    }
};
