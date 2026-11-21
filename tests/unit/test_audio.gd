extends "res://tests/unit/unit_test_base.gd"
## Sound mapping rules (no playback): loudness from speed, pitch from size and
## fill, material resonances, pour loudness, and the sample files themselves.


func test_impact_loudness_rises_with_speed() -> void:
	check(AudioDirector.impact_gain_db(AudioDirector.MIN_IMPACT_SPEED_M_S) <= -29.9, "the slowest audible contact is very quiet")
	check(absf(AudioDirector.impact_gain_db(AudioDirector.FULL_IMPACT_SPEED_M_S)) < 1e-4, "a hard knock plays at full level")
	check(absf(AudioDirector.impact_gain_db(50.0)) < 1e-4, "faster than full does not get louder")
	var last: float = -100.0
	var rising: bool = true
	for i: int in 30:
		var db: float = AudioDirector.impact_gain_db(0.12 + float(i) * 0.1)
		rising = rising and db >= last
		last = db
	check(rising, "loudness never falls as speed rises")
	# A gentle set-down should already be clearly audible, not buried.
	check(AudioDirector.impact_gain_db(0.5) > -20.0, "a gentle set-down is audible (%.1f dB)" % AudioDirector.impact_gain_db(0.5))


func test_vessel_pitch_follows_size_and_fill() -> void:
	var vial: float = AudioDirector.vessel_pitch(0.016, 0.0)
	var flask: float = AudioDirector.vessel_pitch(0.047, 0.0)
	check(vial > flask, "a vial rings higher than a round flask (%.2f vs %.2f)" % [vial, flask])
	check(AudioDirector.vessel_pitch(0.03, 1.0) < AudioDirector.vessel_pitch(0.03, 0.0), "a full vessel rings lower than an empty one")
	check(AudioDirector.vessel_pitch(0.0001, 0.0) <= 1.45 and AudioDirector.vessel_pitch(10.0, 1.0) >= 0.5, "pitch stays in a sane range")


func test_materials_map_to_their_own_resonance() -> void:
	var seen: Dictionary = {}
	for material: StringName in [&"glass", &"ceramic", &"iron", &"wood", &"stone", &"crystal", &"soft"]:
		var sound: StringName = AudioDirector.impact_sound(material)
		check(AudioDirector.CATALOG.has(sound), "%s has an impact sound" % material)
		seen[sound] = true
	check(seen.size() == 7, "every material sounds different")
	check(AudioDirector.impact_sound(&"unknown") == &"impact_wood", "unknown materials fall back to wood")
	check(AudioDirector.material_of(null) == &"wood", "no body counts as the wooden bench")
	var tagged: Node = Node.new()
	tagged.set_meta(&"sound_material", &"iron")
	check(AudioDirector.material_of(tagged) == &"iron", "a sound_material tag overrides the default")
	tagged.free()


func test_pour_loudness() -> void:
	check(AudioDirector.pour_gain(1e-7) >= 0.12, "a dribble is still faintly audible")
	check(AudioDirector.pour_gain(2.5e-5) >= 0.99, "25 mL/s is a full-voiced pour")
	check(AudioDirector.pour_gain(1e-5) < AudioDirector.pour_gain(2e-5), "a faster pour is louder")


func test_every_catalogued_sample_exists_and_is_sound() -> void:
	var total_s: float = 0.0
	for sound: StringName in AudioDirector.CATALOG:
		var count: int = AudioDirector.CATALOG[sound]
		for v: int in count:
			var path: String = AudioDirector.AUDIO_DIR + String(sound) + ("" if count == 1 else "_%d" % (v + 1)) + ".wav"
			var stream: AudioStreamWAV = load(path) as AudioStreamWAV
			check(stream != null, "%s loads" % path)
			if stream == null:
				continue
			var length: float = stream.get_length()
			total_s += length
			check(not stream.stereo and stream.mix_rate == 32000, "%s is 32 kHz mono" % path)
			if String(sound).ends_with("_loop"):
				check(length >= 1.4, "%s is long enough not to sound like a loop (%.1f s)" % [path, length])
			else:
				check(length > 0.03 and length < 4.0, "%s is a one-shot of sensible length (%.2f s)" % [path, length])
	check(total_s < 120.0, "the whole sound set stays small (%.0f s)" % total_s)
