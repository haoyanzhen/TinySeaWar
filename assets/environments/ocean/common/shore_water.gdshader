shader_type canvas_item;
render_mode unshaded;
uniform float animation_time = 0.0;
uniform float shoreline_strength = 0.30;
void fragment() {
 vec4 land = texture(TEXTURE, UV);
 // Visual alpha only: never feeds collision, navigation or water legality.
 float phase = animation_time * 0.85 + sin(UV.x * 31.0 + UV.y * 17.0) * 2.0;
 float cycle = fract(phase / 6.283185);
 float radius = mix(1.5, 7.0, cycle);
 vec2 offset = TEXTURE_PIXEL_SIZE * radius;
 float edge = max(max(texture(TEXTURE, UV + vec2(offset.x, 0.0)).a, texture(TEXTURE, UV - vec2(offset.x, 0.0)).a), max(texture(TEXTURE, UV + vec2(0.0, offset.y)).a, texture(TEXTURE, UV - vec2(0.0, offset.y)).a));
 vec2 inner_offset = offset * 0.55;
 float inner = max(max(texture(TEXTURE, UV + vec2(inner_offset.x, 0.0)).a, texture(TEXTURE, UV - vec2(inner_offset.x, 0.0)).a), max(texture(TEXTURE, UV + vec2(0.0, inner_offset.y)).a, texture(TEXTURE, UV - vec2(0.0, inner_offset.y)).a));
 float breakup = smoothstep(-0.4, 0.7, sin(UV.x * 143.0 + sin(UV.y * 97.0) * 2.0));
 float wave = max(0.0, edge - inner) * sin(cycle * 3.14159) * breakup * shoreline_strength * (1.0 - land.a);
 float alpha = land.a + wave * (1.0 - land.a);
 vec3 rgb = (land.rgb * land.a + vec3(0.48,0.76,0.79) * wave * (1.0-land.a)) / max(alpha, 0.0001);
 COLOR = vec4(rgb, alpha);
}
