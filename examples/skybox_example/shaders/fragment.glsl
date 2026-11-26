#version 450 core
in vec2 v_uv;

layout(location = 2) uniform sampler2D u_texture;

out vec4 frag;

void main() {
    vec4 c = texture(u_texture, v_uv);
    if (c.a < 0.01) discard;
    frag = c;
}

