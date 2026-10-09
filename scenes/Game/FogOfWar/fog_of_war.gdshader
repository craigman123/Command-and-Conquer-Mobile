shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D visible_tex : filter_linear;
uniform sampler2D explored_tex : filter_linear;
uniform sampler2D los_tex : filter_linear, repeat_enable;

uniform vec4 units[32];
uniform int unit_count = 0;

uniform vec2 map_min = vec2(-300.0, -300.0);
uniform vec2 map_size = vec2(600.0, 600.0);
uniform float edge_thresh = 0.6;
uniform float ground_y = 0.0;
uniform float shroud_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float explored_brightness : hint_range(0.0, 1.0) = 0.15;
uniform float unexplored_brightness : hint_range(0.0, 1.0) = 0.0;
uniform float explored_color : hint_range(0.0, 1.0) = 0.9;
uniform float wall_extend = 30.0;

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
const bool compat_depth = true;
#else
const bool compat_depth = false;
#endif

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec3 scene = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;

	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	float z = compat_depth ? depth * 2.0 - 1.0 : depth;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, z);
	vec4 w4 = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 wpos = w4.xyz / w4.w;

		vec2 world = wpos.xz;
	vec2 uv = (world - map_min) / map_size;
	bool has_geo = compat_depth ? (depth < 1.0) : (depth > 0.0);
	bool inside = has_geo && all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)));

	vec3 dx = dFdx(wpos);
	vec3 dy = dFdy(wpos);
	vec3 n = normalize(cross(dx, dy));
	if (dot(n, INV_VIEW_MATRIX[3].xyz - wpos) < 0.0) n = -n;
	// Thin objects and depth jumps (branches, tree edges) give junk normals, so they don't count as walls
	bool smooth_surf = max(length(dx), length(dy)) < edge_thresh;
	bool is_wall = smooth_surf && abs(n.y) < 0.7;

	float vis = 0.0;
	if (inside) {
		for (int i = 0; i < 32; i++) {
			if (i >= unit_count) break;
			vec2 dv = world - units[i].xy;
			float d = length(dv);
			float u = (atan(dv.y, dv.x) + PI) / TAU;
			float lim = textureLod(los_tex, vec2(u, (float(i) + 0.5) / 32.0), 0.0).r * units[i].z;
			if (is_wall) lim = min(lim + wall_extend, units[i].z);
			vis = max(vis, 1.0 - smoothstep(lim - 1.0, lim, d));
		}
	}

	vec2 es = clamp(((is_wall ? world + n.xz * 3.0 : world) - map_min) / map_size, 0.0, 1.0);
	float seen = inside ? smoothstep(0.3, 0.7, textureLod(explored_tex, es, 0.0).r) : 0.0;

	vec3 lum = vec3(dot(scene, vec3(0.299, 0.587, 0.114)));
	vec3 grey = mix(lum, scene, explored_color) * explored_brightness;
	vec3 shroud = mix(scene, lum * unexplored_brightness, shroud_alpha);
	ALBEDO = mix(mix(shroud, grey, seen), scene, vis);
	ALPHA = 1.0;
}