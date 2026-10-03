shader_type spatial;
// Материал окружения: текстура + нормали, тонировка цветом вершин,
// «грязь» по миру против повторов, затемнение у земли (контактная тень).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float normal_strength = 1.0;
uniform float roughness = 0.85;
uniform float metallic = 0.0;
uniform float specular_amount = 0.35;
uniform float grime_amount = 0.22;
uniform float grime_scale = 0.06;
uniform float ground_ao = 0.42;
uniform float ground_ao_height = 1.2;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 albedo = texture(albedo_tex, UV).rgb * COLOR.rgb;
	// крупные пятна грязи/выгорания, чтобы плитка не повторялась
	float g = texture(grime_tex, world_pos.xz * grime_scale + vec2(world_pos.y * 0.05)).r;
	albedo *= mix(1.0, 0.72 + g * 0.5, grime_amount * 2.0);
	// контактная тень у земли для стен и предметов (не для пола)
	float vertical = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float ao = mix(1.0 - ground_ao, 1.0, smoothstep(0.0, ground_ao_height, world_pos.y));
	albedo *= mix(1.0, ao, vertical);
	ALBEDO = albedo;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular_amount;
}
