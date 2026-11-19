const std = @import("std");

pub const Vec3 = [3]f32;
pub const Mat4 = [16]f32;

pub fn sub(a: Vec3, b: Vec3) Vec3 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}

pub fn add(a: Vec3, b: Vec3) Vec3 {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}

pub fn dot(a: Vec3, b: Vec3) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

pub fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

pub fn normalize(a: Vec3) Vec3 {
    const l = @sqrt(dot(a, a));
    return .{ a[0] / l, a[1] / l, a[2] / l };
}

pub fn identity() Mat4 {
    return .{
        1, 0, 0, 0, //
        0, 1, 0, 0, //
        0, 0, 1, 0, //
        0, 0, 0, 1, //
    };
}

pub fn mul(a: Mat4, b: Mat4) Mat4 {
    var r: Mat4 = undefined;
    for (0..4) |col| {
        for (0..4) |row| {
            var s: f32 = 0;
            for (0..4) |k| s += a[k * 4 + row] * b[col * 4 + k];
            r[col * 4 + row] = s;
        }
    }
    return r;
}

pub fn translate(x: f32, y: f32, z: f32) Mat4 {
    var m = identity();
    m[12] = x;
    m[13] = y;
    m[14] = z;
    return m;
}

pub fn scale(x: f32, y: f32, z: f32) Mat4 {
    var m = identity();
    m[0] = x;
    m[5] = y;
    m[10] = z;
    return m;
}

pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) Mat4 {
    const f = 1.0 / @tan(fovy / 2.0);
    var m = [_]f32{0} ** 16;
    m[0] = f / aspect;
    m[5] = f;
    m[10] = (far + near) / (near - far);
    m[11] = -1;
    m[14] = (2 * far * near) / (near - far);
    return m;
}

pub fn lookAt(eye: Vec3, target: Vec3, up: Vec3) Mat4 {
    const f = normalize(sub(target, eye));
    const s = normalize(cross(f, up));
    const u = cross(s, f);
    return .{
        s[0], u[0], -f[0], 0, //
        s[1], u[1], -f[1], 0, //
        s[2], u[2], -f[2], 0, //
        -dot(s, eye), -dot(u, eye), dot(f, eye), 1, //
    };
}
