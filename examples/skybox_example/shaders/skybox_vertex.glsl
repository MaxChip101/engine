#version 450 core
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec2 a_uv;

layout(location = 0) uniform mat4 u_model;
layout(location = 1) uniform mat4 u_view_proj;

out vec3 v_dir;

void main() {
    v_dir = a_pos;
    gl_Position = (u_view_proj * vec4(a_pos, 1.0)).xyww;
}


