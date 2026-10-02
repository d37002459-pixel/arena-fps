extends RefCounted
## Процедурные звуки: генерируются кодом при первом использовании, файлов не нужно.

const RATE := 22050
static var _cache := {}


static func get_sound(sound_name: String) -> AudioStreamWAV:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var length := 0.3
	match sound_name:
		"shot": length = 0.55
		"dry": length = 0.08
		"mag_out": length = 0.18
		"mag_in": length = 0.2
		"bolt": length = 0.25
		"hit": length = 0.12
		"headshot": length = 0.45
		"kill": length = 0.5
		"land": length = 0.3
		"hurt": length = 0.3
		"step": length = 0.09
	var s := _make(sound_name, length)
	_cache[sound_name] = s
	return s


static func _make(kind: String, length: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.3
		lp2 += (noise - lp2) * 0.05
		var v := 0.0
		match kind:
			"shot":
				var crack := noise * exp(-t * 70.0) * 0.9
				var body := lp * exp(-t * 16.0) * 1.1
				var thump := sin(TAU * 58.0 * t) * exp(-t * 20.0) * 0.9
				var tail := lp2 * exp(-t * 6.0) * 2.2
				v = tanh((crack + body + thump + tail) * 1.4) * 0.9
			"dry":
				v = (noise * exp(-t * 300.0) + sin(TAU * 2600.0 * t) * exp(-t * 120.0)) * 0.5
			"mag_out":
				v = _click(t, 0.0, noise, 900.0) + lp2 * exp(-t * 20.0) * 1.5
			"mag_in":
				v = _click(t, 0.0, noise, 700.0) * 0.7 + _click(t, 0.07, noise, 1100.0)
			"bolt":
				v = _click(t, 0.0, noise, 1300.0) * 0.8 + _click(t, 0.11, noise, 1600.0)
			"hit":
				v = sin(TAU * 1400.0 * t) * exp(-t * 40.0) * 0.45 + sin(TAU * 2100.0 * t) * exp(-t * 55.0) * 0.25
			"headshot":
				v = sin(TAU * 1900.0 * t) * exp(-t * 11.0) * 0.4 + sin(TAU * 2850.0 * t) * exp(-t * 13.0) * 0.22
			"kill":
				v = sin(TAU * 880.0 * t) * exp(-t * 9.0) * 0.3 + sin(TAU * 1320.0 * t) * exp(-maxf(t - 0.08, 0.0) * 9.0) * (0.3 if t > 0.08 else 0.0)
			"land":
				v = lp2 * exp(-t * 16.0) * 3.5 + sin(TAU * 48.0 * t) * exp(-t * 18.0) * 0.6
			"hurt":
				v = sin(TAU * 120.0 * t) * exp(-t * 9.0) * 0.6 + lp * exp(-t * 18.0) * 0.6
			"step":
				v = lp2 * exp(-t * 45.0) * 3.0 + lp * exp(-t * 80.0) * 0.3
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


static func _click(t: float, t0: float, noise: float, freq: float) -> float:
	if t < t0:
		return 0.0
	var d := t - t0
	return noise * exp(-d * 150.0) * 0.8 + sin(TAU * freq * d) * exp(-d * 70.0) * 0.5
