shader_type spatial;
// Мягкая тень на полу вокруг стен и предметов: полупрозрачная тёмная «подложка».
// (Обычное смешивание вместо умножения: в режиме Compatibility умножение в тени даёт чёрные пятна.)
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float strength = 0.35;

void fragment() {
	// UV: 0.5 — у предмета (темно), 0 или 1 — край (без тени)
	vec2 d = abs(UV - 0.5) * 2.0;
	float k = clamp(1.0 - length(d), 0.0, 1.0);
	k = k * k * (3.0 - 2.0 * k);
	ALBEDO = vec3(0.08, 0.06, 0.04);
	ALPHA = k * strength;
}
