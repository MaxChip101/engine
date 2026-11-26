#version 450 core
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec2 a_uv;

layout(location = 0) uniform mat4 u_model;
layout(location = 1) uniform mat4 u_view_proj;

out vec2 v_uv;

void main() {
    v_uv = a_uv;
    gl_Position = u_view_proj * u_model * vec4(a_pos, 1.0);
}


