const std = @import("std");
const mem = std.mem;

const sdl = @import("sdl3");

// impl audio from sdl
pub const Audio = struct {
    allocator: mem.Allocator,

    const Self = @This();

    pub fn init(allocator: mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.*.allocator = allocator;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }
};
