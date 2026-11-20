shader_type spatial;
// Sea surface for Boat Sink v2.
// Vertex displacement = sum of 3 directional sine waves.
// BoatBody.water_height_at() in boat.gd computes EXACTLY the same sum
// (same dirs / frequencies / speeds / amplitudes, same wave_time uniform
// fed from the boat's physics clock) so buoyancy matches the visuals.

uniform float wave_time = 0.0;
uniform vec3 deep_color : source_color = vec3(0.0, 0.17, 0.30);
uniform vec3 shallow_color : source_color = vec3(0.02, 0.44, 0.52);
uniform vec3 sky_color : source_color = vec3(0.38, 0.64, 0.78);

varying vec3 world_pos;

float wave_height(vec2 p, float t) {
	float h = 0.0;
	h += 0.140 * sin((p.x * 0.92 + p.y * 0.39) * 1.05 + t * 1.15);
	h += 0.090 * sin((p.x * -0.52 + p.y * 0.86) * 1.65 + t * 1.55);
	h += 0.045 * sin((p.x * 0.98 + p.y * -0.20) * 3.10 + t * 2.30);
	return h;
}

vec2 wave_slope(vec2 p, float t) {
	vec2 s = vec2(0.0);
	s += 0.140 * cos((p.x * 0.92 + p.y * 0.39) * 1.05 + t * 1.15) * 1.05 * vec2(0.92, 0.39);
	s += 0.090 * cos((p.x * -0.52 + p.y * 0.86) * 1.65 + t * 1.55) * 1.65 * vec2(-0.52, 0.86);
	s += 0.045 * cos((p.x * 0.98 + p.y * -0.20) * 3.10 + t * 2.30) * 3.10 * vec2(0.98, -0.20);
	return s;
}

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	float h = wave_height(wp.xz, wave_time);
	VERTEX.y += h;
	vec2 s = wave_slope(wp.xz, wave_time);
	NORMAL = normalize(vec3(-s.x, 1.0, -s.y));
	world_pos = wp.xyz + vec3(0.0, h, 0.0);
}

void fragment() {
	vec2 s = wave_slope(world_pos.xz, wave_time);
	// high-frequency ripple detail (normal perturbation only, not in buoyancy)
	float t = wave_time;
	vec2 d = vec2(0.0);
	d += 0.006 * cos((world_pos.x * 0.80 + world_pos.z * 0.60) * 9.0 + t * 3.0) * 9.0 * vec2(0.80, 0.60);
	d += 0.004 * cos((world_pos.x * -0.34 + world_pos.z * 0.94) * 14.0 + t * 4.2) * 14.0 * vec2(-0.34, 0.94);
	vec2 total = (s + d) * 0.72;
	vec3 wn = normalize(vec3(-total.x, 1.0, -total.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float crest = clamp(0.50 + world_pos.y * 0.55, 0.0, 1.0);
	vec3 col = mix(deep_color, shallow_color, crest);
	col = mix(col, sky_color, fres * 0.18);
	ALBEDO = col;
	ROUGHNESS = 0.38;
	SPECULAR = 0.38;
	METALLIC = 0.0;
}
