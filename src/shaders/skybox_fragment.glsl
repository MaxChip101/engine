#version 450 core
in vec3 v_dir;

layout(location = 2) uniform samplerCube u_texture;

out vec4 frag;

void main() {
    vec4 c = texture(u_texture, v_dir);
    if (c.a < 0.01) discard;
    frag = c;
}

