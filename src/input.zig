const std = @import("std");

const sdl = @import("sdl3");

pub const ButtonType = enum(usize) {
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

    const Self = @This();

    pub fn fromScancode(code: sdl.SDL_Scancode) ?Self {
        return switch (code) {
            sdl.SDL_SCANCODE_0 => .@"0",
            sdl.SDL_SCANCODE_1 => .@"1",
            sdl.SDL_SCANCODE_2 => .@"2",
            sdl.SDL_SCANCODE_3 => .@"3",
            sdl.SDL_SCANCODE_4 => .@"4",
            sdl.SDL_SCANCODE_5 => .@"5",
            sdl.SDL_SCANCODE_6 => .@"6",
            sdl.SDL_SCANCODE_7 => .@"7",
            sdl.SDL_SCANCODE_8 => .@"8",
            sdl.SDL_SCANCODE_9 => .@"9",
            sdl.SDL_SCANCODE_A => .A,
            sdl.SDL_SCANCODE_B => .B,
            sdl.SDL_SCANCODE_C => .C,
            sdl.SDL_SCANCODE_D => .D,
            sdl.SDL_SCANCODE_E => .E,
            sdl.SDL_SCANCODE_F => .F,
            sdl.SDL_SCANCODE_G => .G,
            sdl.SDL_SCANCODE_H => .H,
            sdl.SDL_SCANCODE_I => .I,
            sdl.SDL_SCANCODE_J => .J,
            sdl.SDL_SCANCODE_K => .K,
            sdl.SDL_SCANCODE_L => .L,
            sdl.SDL_SCANCODE_M => .M,
            sdl.SDL_SCANCODE_N => .N,
            sdl.SDL_SCANCODE_O => .O,
            sdl.SDL_SCANCODE_P => .P,
            sdl.SDL_SCANCODE_Q => .Q,
            sdl.SDL_SCANCODE_R => .R,
            sdl.SDL_SCANCODE_S => .S,
            sdl.SDL_SCANCODE_T => .T,
            sdl.SDL_SCANCODE_U => .U,
            sdl.SDL_SCANCODE_V => .V,
            sdl.SDL_SCANCODE_W => .W,
            sdl.SDL_SCANCODE_X => .X,
            sdl.SDL_SCANCODE_Y => .Y,
            sdl.SDL_SCANCODE_Z => .Z,
            sdl.SDL_SCANCODE_SPACE => .Space,
            sdl.SDL_SCANCODE_LSHIFT => .LeftShift,
            sdl.SDL_SCANCODE_RSHIFT => .RightShift,
            sdl.SDL_SCANCODE_ESCAPE => .Escape,
            sdl.SDL_SCANCODE_LCTRL => .LeftControl,
            sdl.SDL_SCANCODE_RCTRL => .RightControl,
            sdl.SDL_SCANCODE_TAB => .Tab,
            sdl.SDL_SCANCODE_RETURN => .Return,
            sdl.SDL_SCANCODE_BACKSPACE => .BackSpace,
            sdl.SDL_SCANCODE_LALT => .LeftAlt,
            sdl.SDL_SCANCODE_RALT => .RightAlt,
            sdl.SDL_SCANCODE_LEFT => .Left,
            sdl.SDL_SCANCODE_UP => .Up,
            sdl.SDL_SCANCODE_DOWN => .Down,
            sdl.SDL_SCANCODE_RIGHT => .Right,
            else => null,
        };
    }

    pub fn fromMouseButton(btn: u8) ?Self {
        return switch (btn) {
            sdl.SDL_BUTTON_LEFT => .MouseLeft,
            sdl.SDL_BUTTON_RIGHT => .MouseRight,
            sdl.SDL_BUTTON_MIDDLE => .MouseMiddle,
            else => null,
        };
    }
};

const button_len = @typeInfo(ButtonType).@"enum".fields.len;

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
                    if (ButtonType.fromScancode(event.key.scancode)) |b| self.pressButton(b);
                }
            },
            sdl.SDL_EVENT_KEY_UP => {
                if (!event.key.repeat) {
                    if (ButtonType.fromScancode(event.key.scancode)) |b| self.releaseButton(b);
                }
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                if (ButtonType.fromMouseButton(event.button.button)) |b| self.pressButton(b);
            },
            sdl.SDL_EVENT_MOUSE_BUTTON_UP => {
                if (ButtonType.fromMouseButton(event.button.button)) |b| self.releaseButton(b);
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

    fn pressButton(self: *Input, b: ButtonType) void {
        const idx = @intFromEnum(b);
        if (!self.down[idx]) self.pressed[idx] = true;
        self.down[idx] = true;
    }

    fn releaseButton(self: *Input, b: ButtonType) void {
        const idx = @intFromEnum(b);
        if (self.down[idx]) self.released[idx] = true;
        self.down[idx] = false;
    }

    pub fn isDown(self: Input, b: ButtonType) bool {
        return self.down[@intFromEnum(b)];
    }

    pub fn isPressed(self: Input, b: ButtonType) bool {
        return self.pressed[@intFromEnum(b)];
    }

    pub fn isReleased(self: Input, b: ButtonType) bool {
        return self.released[@intFromEnum(b)];
    }
};
