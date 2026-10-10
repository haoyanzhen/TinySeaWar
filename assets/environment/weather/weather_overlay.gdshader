shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec2 map_size = vec2(4096.0, 2304.0);
uniform float animation_time = 0.0;
uniform float animation_speed = 1.0;
uniform float atmosphere_strength = 0.0;
uniform float weather_detail_scale = 1.0;
uniform float lightning_flash = 0.0;
uniform float detail_activity = 1.0;
uniform int focus_count = 0;
uniform vec2 focus_points[24];
uniform float focus_radius = 180.0;
uniform vec2 aim_position = vec2(0.0);
uniform bool aim_active = false;
uniform sampler2D weather_cloud_texture : filter_linear;
uniform sampler2D foam_texture : filter_linear;
uniform sampler2D rain_line_texture : filter_linear;
uniform sampler2D rain_ripple_texture : filter_linear;
uniform sampler2D storm_shadow_texture : filter_linear;
uniform sampler2D lightning_mask_texture : filter_linear;
uniform sampler2D snow_flake_texture : filter_linear;
uniform sampler2D snow_haze_texture : filter_linear;
uniform vec4 highlight_color : source_color = vec4(0.72, 0.89, 0.90, 1.0);
uniform vec4 cloud_color : source_color = vec4(0.05, 0.17, 0.25, 1.0);
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.0;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.0;
uniform float rain_strength : hint_range(0.0, 1.0) = 0.0;
uniform float mist_strength : hint_range(0.0, 1.0) = 0.0;
uniform float lightning_strength : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_scale : hint_range(0.25, 2.0) = 1.0;
uniform float rain_angle : hint_range(-3.14159, 3.14159) = -0.55;
uniform float rain_density : hint_range(0.0, 2.0) = 1.0;
uniform float rain_line_strength : hint_range(0.0, 2.0) = 1.0;
uniform float rain_ripple_strength : hint_range(0.0, 2.0) = 1.0;
uniform float squall_strength : hint_range(0.0, 1.0) = 0.0;
uniform float snow_strength : hint_range(0.0, 1.0) = 0.0;
uniform float snow_haze_strength : hint_range(0.0, 1.0) = 0.0;

varying vec2 local_position;

float hash21(vec2 point) {
	point = fract(point * vec2(123.34, 456.21));
	point += dot(point, point + 45.32);
	return fract(point.x * point.y);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

float fbm(vec2 point) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int index = 0; index < 4; index++) {
		value += value_noise(point) * amplitude;
		point = point * 2.03 + vec2(17.1, 9.2);
		amplitude *= 0.5;
	}
	return value;
}

// Soft local reduction only affects fine detail; broad weather never opens holes.
float detail_visibility(vec2 world) {
 float protection = 0.0;
 for (int i = 0; i < 24; i++) {
  if (i >= focus_count) { break; }
  protection = max(protection, 1.0 - smoothstep(focus_radius * 0.25, focus_radius, distance(world, focus_points[i])));
 }
 if (aim_active) {
  protection = max(protection, 1.0 - smoothstep(focus_radius * 0.35, focus_radius * 1.5, distance(world, aim_position)));
 }
 return (1.0 - protection * 0.72) * detail_activity;
}

// A drop and its impact share a stationary world-space endpoint and lifetime.
// The slight downward screen projection is an illustration convention; gravity
// in a strict overhead view points into the image, not towards a screen edge.
vec2 rainfall(vec2 world, float clock, float density) {
 vec2 cell = floor(world / 128.0);
 vec2 local = world - cell * 128.0;
 float phase = hash21(cell + 7.0);
 float period = 0.95 + hash21(cell + 21.0) * 0.45;
 float sequence = floor(clock / period + phase);
 float age = fract(clock / period + phase) * period;
 vec2 event_cell = cell + vec2(sequence * 13.17, sequence * 7.31);
 float seed = hash21(event_cell);
 vec2 endpoint = vec2(56.0,80.0) + vec2(hash21(event_cell+11.0), hash21(event_cell+31.0)) * 16.0;
 float falling = (0.24 + seed * 0.12) * 1.20;
 vec2 direction = normalize(vec2(sin(rain_angle) * 0.65, 1.0));
 float progress = clamp(age / falling, 0.0, 1.0);
 vec2 head = endpoint - direction * 43.2 * (1.0 - progress);
 vec2 d = local - head;
 float along = dot(d, direction);
 float across = abs(dot(d, vec2(-direction.y, direction.x)));
 float width = max(length(fwidth(world)) * 0.76, 1.20);
 float streak_length = mix(28.8 + seed * 5.76, 0.0, smoothstep(0.75,1.0,progress));
 // Transparent feathered tail; retain a small crisp leading core.
 float tail = clamp(-along/max(streak_length,0.001),0.0,1.0);
 float taper = mix(1.0,0.68,smoothstep(0.35,1.0,tail));
 float core = 1.0-smoothstep(width*0.12*taper,width*taper,across);
 float softness = 1.0-smoothstep(width*0.5,width*1.65,across);
 float stroke = (core*0.78+softness*0.22) * (1.0-smoothstep(0.45,1.0,tail));
 stroke *= smoothstep(-streak_length-1.0,-streak_length+2.0,along) * (1.0-smoothstep(0.0,2.0,along));
 stroke *= smoothstep(0.0,0.04,age) * (1.0-step(falling,age));
 float impact_age = age-falling;
 float impact_life = clamp(impact_age/0.38,0.0,1.0);
 vec2 impact_delta = local-endpoint;
 float radius = 1.0 + impact_life * 14.0;
 float ring = 1.0-smoothstep(width*0.5,width*1.2,abs(length(impact_delta)-radius));
 float arcs = smoothstep(-0.15,0.40,sin(atan(impact_delta.y,impact_delta.x)*2.0+seed*6.28));
 float spark = (1.0-smoothstep(0.0,3.5,length(impact_delta))) * (1.0-smoothstep(0.0,0.07,impact_age));
 float impact = (ring*arcs*0.75+spark) * (1.0-impact_life) * step(0.0,impact_age) * (1.0-step(0.38,impact_age));
 float active = step(seed,min(0.9,density*0.58));
 return vec2(stroke,impact)*active;
}

// Short branching intracloud discharge, without a surface strike endpoint.
float segment_distance(vec2 p, vec2 a, vec2 b) {
 vec2 ab = b-a;
 return length(p-a-ab*clamp(dot(p-a,ab)/max(dot(ab,ab),0.0001),0.0,1.0));
}
// Each segment has a bright narrow core and a much weaker soft halo.
float discharge_stroke(vec2 p, vec2 a, vec2 b, float width, float pixel_width) {
 float d=segment_distance(p,a,b);
 float aa=max(pixel_width*0.48,0.6);
 return (1.0-smoothstep(width-aa,width+aa,d))*0.82
      + (1.0-smoothstep(width,width+aa*3.0,d))*0.18;
}
float cloud_discharge(vec2 p, vec2 seed, float pixel_width) {
 float light=0.0;
 vec2 start=vec2(-210.0,(hash21(seed+13.0)-0.5)*70.0);
 float drift=(hash21(seed+27.0)-0.5)*18.0;
 int first_fork=3+int(floor(hash21(seed+73.0)*5.0));
 int second_fork=10+int(floor(hash21(seed+81.0)*4.0));
 for (int i=0; i<18; i++) {
  float n=float(i);
  vec2 key=seed+vec2(n*7.37,n*3.19);
  // Unequal forward steps and correlated drift avoid alternating sawteeth.
  vec2 end=start+vec2(13.0+hash21(key+5.0)*21.0,
       drift+(hash21(key+17.0)-0.5)*43.0);
  vec2 mid=mix(start,end,0.27+hash21(key+33.0)*0.38);
  mid.y+=(hash21(key+49.0)-0.5)*12.0;
  float width=mix(2.3,0.55,n/18.0);
  float fade=1.0-smoothstep(13.0,18.0,n);
  light=max(light,discharge_stroke(p,start,mid,width,pixel_width)*fade);
  light=max(light,discharge_stroke(p,mid,end,width*0.92,pixel_width)*fade);
  if (i==first_fork || i==second_fork) {
   vec2 fork_start=mid;
   float side=hash21(key+61.0)>0.5 ? 1.0 : -1.0;
   float angle=side*(0.55+hash21(key+79.0)*0.65);
   vec2 forward=vec2(cos(angle),sin(angle));
   vec2 across=vec2(-forward.y,forward.x);
   for (int j=0;j<6;j++) {
    float m=float(j);
    vec2 branch_seed=key+vec2(m*11.31,91.0+m*2.17);
    vec2 fork_end=fork_start+forward*(9.0+hash21(branch_seed)*17.0)
        +across*(hash21(branch_seed+19.0)-0.5)*19.0;
    float taper=1.0-m/6.0;
    light=max(light,discharge_stroke(p,fork_start,fork_end,width*0.65*taper,pixel_width)*taper*0.72);
    fork_start=fork_end;
   }
  }
  start=end;
 }
 return light;
}

vec4 atmosphere(vec2 world) {
 float t = animation_time;
 mat2 rotation = mat2(vec2(0.819,-0.574),vec2(0.574,0.819));
 vec2 flow = world * (0.0012 * max(0.6,cloud_scale)) + vec2(t*0.025,-t*0.011);
 float authored = texture(weather_cloud_texture, fract(rotation*world/2300.0 + vec2(t*0.0015,-t*0.0006))).r;
 float field = fbm(flow) * 0.85 + authored * 0.15;
 float cloud = smoothstep(0.30,0.55,field);
 float storm = texture(storm_shadow_texture, fract(rotation*world/1900.0 + vec2(-t*0.0011,t*0.0005))).r;
 float shade = cloud * (0.26 + cloud_opacity*0.50) + storm*squall_strength*0.14;
 vec3 premul = cloud_color.rgb * shade;
 float alpha = shade;
 float detail = detail_visibility(world);
 float gust = 0.62 + 0.38 * smoothstep(0.26,0.72,fbm(world*0.00085+vec2(t*0.033,-t*0.012)+71.0));
 vec2 drops = rainfall(world,t*0.35,rain_density*weather_detail_scale);
 float rain = drops.x * rain_strength * rain_line_strength * 0.60 * gust * detail;
 float impact = drops.y * rain_strength * rain_ripple_strength * 0.52 * gust * detail;
 float foam = texture(foam_texture,fract(rotation*world/1300.0+vec2(-t*0.0016,t*0.0008))).r;
 float foam_alpha = smoothstep(0.40,0.88,foam) * foam_strength * 0.12 * gust * detail;
 vec3 rain_color = vec3(0.70,0.83,0.89);
 float bright_alpha = rain + impact + foam_alpha;
 premul = premul * (1.0-bright_alpha) + rain_color * bright_alpha;
 alpha = alpha + bright_alpha * (1.0-alpha);
 float mist = mist_strength * 0.12 * smoothstep(0.28,0.70,field);
 premul = premul*(1.0-mist) + vec3(0.40,0.54,0.61)*mist;
 alpha += mist*(1.0-alpha);
 float flash_mask = texture(lightning_mask_texture,fract(rotation*world/2100.0+vec2(0.19,0.41))).r;
 // A different cloud bank is illuminated by each discharge. No ground strike
 // or gameplay impact is implied by this environment-only light.
 float event = floor(t/12.0);
 vec2 bank_cell = floor(world/1600.0);
 vec2 bank_uv = fract(world/1600.0);
 vec2 event_seed = bank_cell + vec2(event*17.0,event*9.0);
 vec2 light_center = vec2(0.25) + vec2(hash21(event_seed+8.0),hash21(event_seed+29.0))*0.50;
 // Sample neighboring cloud lights in continuous world space. Never fade at
 // cell edges: independent per-cell fades expose a rectangular illumination grid.
 float glow=0.0;
 if (lightning_flash>0.001 && lightning_strength>0.0) {
  for (int y=-1;y<=1;y++) {
   for (int x=-1;x<=1;x++) {
    vec2 neighbor=vec2(float(x),float(y));
    vec2 light_seed=bank_cell+neighbor+vec2(event*17.0,event*9.0);
    vec2 center=vec2(0.25)+vec2(hash21(light_seed+8.0),hash21(light_seed+29.0))*0.50;
    vec2 delta=bank_uv-neighbor-center;
    float reach=0.76+hash21(light_seed+53.0)*0.16;
    float pool=1.0-smoothstep(0.06,reach,length(delta*vec2(1.0,1.08)));
    glow+=pool*(0.66+hash21(light_seed+71.0)*0.25);
   }
  }
 }
 glow=1.0-exp(-glow*1.3);
 float flash = lightning_flash * lightning_strength * (0.02+glow*(0.34+0.32*cloud+0.15*flash_mask));
 premul = premul*(1.0-flash) + vec3(0.78,0.88,1.0)*flash;
 alpha += flash*(1.0-alpha);
 // A few banks expose a fine channel inside the wider illuminated cloud.
 float channel=0.0;
 float pixel_width=length(fwidth(world));
 if (lightning_flash>0.001 && lightning_strength>0.0) {
  vec2 q=(bank_uv-light_center)*1600.0;
  float orientation=hash21(event_seed+61.0)*6.28318;
  q=mat2(vec2(cos(orientation),-sin(orientation)),vec2(sin(orientation),cos(orientation)))*q;
  channel=cloud_discharge(q,event_seed,pixel_width)*step(0.40,hash21(event_seed+47.0));
  channel*=lightning_flash*lightning_strength*detail;
 }
 premul=premul*(1.0-channel)+vec3(0.86,0.94,1.0)*channel;
 alpha+=channel*(1.0-alpha);
 return vec4(premul/max(alpha,0.0001),min(alpha,0.48+channel*0.30));
}

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec2 world = local_position;
	float time = animation_time * animation_speed;
	mat2 texture_rotation = mat2(vec2(0.819, -0.574), vec2(0.574, 0.819));
	float cloud_texture_size = 2048.0 / max(0.25, cloud_scale);
	float cloud_mask = texture(weather_cloud_texture, fract(texture_rotation * world / cloud_texture_size + vec2(time * 0.0005, time * 0.0003))).r;
	float storm_mask = texture(storm_shadow_texture, fract(texture_rotation * world / 1536.0 + vec2(-time * 0.0007, time * 0.0005))).r;
	float cloud_alpha = cloud_mask * cloud_opacity * 0.22 + storm_mask * squall_strength * 0.20;
	vec3 color = cloud_color.rgb;
	float alpha = cloud_alpha;

	vec2 rain_axis = vec2(cos(rain_angle), sin(rain_angle));
	vec2 rain_uv = fract(world / 1024.0 + rain_axis * time * 0.006);
	float rain_mask = texture(rain_line_texture, rain_uv).r;
	float rain_breakup = smoothstep(0.20, 0.86, fbm(world * 0.005 + vec2(time * 0.32, -time * 0.21)));
	float rain_alpha = rain_mask * rain_strength * rain_line_strength * rain_breakup * (0.08 + rain_density * 0.05);
	color = mix(color, highlight_color.rgb, rain_alpha);
	alpha += rain_alpha;

	float ripple_mask = texture(rain_ripple_texture, fract(world / 1024.0 + vec2(time * 0.0004, -time * 0.0003))).r;
	float ripple_alpha = ripple_mask * rain_strength * rain_ripple_strength * 0.035;
	color = mix(color, highlight_color.rgb, ripple_alpha);
	alpha += ripple_alpha;

	float foam_mask = texture(foam_texture, fract(texture_rotation * world / 1024.0 + vec2(-time * 0.0014, time * 0.0007))).r;
	float foam_alpha = foam_mask * foam_strength * 0.055;
	color = mix(color, highlight_color.rgb, foam_alpha);
	alpha += foam_alpha;

	float snow_mask = texture(snow_flake_texture, fract(world / 1024.0 + vec2(-time * 0.0012, time * 0.0024))).r;
	float snow_alpha = smoothstep(0.66, 0.98, snow_mask) * snow_strength * 0.16;
	color = mix(color, vec3(0.88, 0.96, 1.0), snow_alpha);
	alpha += snow_alpha;

	float snow_haze_mask = texture(snow_haze_texture, fract(texture_rotation * world / 1536.0 + vec2(time * 0.0007, time * 0.0002))).r;
	float snow_haze_alpha = snow_haze_mask * snow_haze_strength * 0.14;
	color = mix(color, vec3(0.72, 0.86, 0.93), snow_haze_alpha);
	alpha += snow_haze_alpha;

	float lightning_pulse = pow(smoothstep(0.935, 1.0, sin(time * 0.73) * 0.5 + 0.5), 8.0) * lightning_strength;
	float lightning_mask = texture(lightning_mask_texture, fract(texture_rotation * world / 1536.0 + vec2(0.19, 0.41))).r;
	float lightning_alpha = lightning_pulse * (0.08 + lightning_mask * 0.18);
	color = mix(color, highlight_color.rgb, lightning_alpha);
	alpha += lightning_alpha;

	float screen_mist = mist_strength * (0.04 + rain_strength * 0.035 + snow_haze_strength * 0.04);
	color = mix(color, highlight_color.rgb, screen_mist);
	alpha += screen_mist;

	float map_edge_distance = min(min(world.x, map_size.x - world.x), min(world.y, map_size.y - world.y));
	float map_edge = 1.0 - smoothstep(0.0, 120.0, map_edge_distance);
	alpha *= 1.0 - map_edge * 0.35;
	vec4 legacy = vec4(color, clamp(alpha, 0.0, 0.34));
 if (atmosphere_strength > 0.0) {
  vec4 candidate = atmosphere(world);
  candidate.a *= 1.0 - map_edge * 0.35;
  COLOR = mix(legacy, candidate, atmosphere_strength);
 } else {
  COLOR = legacy;
 }
}
