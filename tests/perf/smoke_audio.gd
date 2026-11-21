extends SceneTree
## Integration smoke test for the sound system on the real bench.
## Usage: godot --headless --path . --script res://tests/perf/smoke_audio.gd
## Checks the director starts, every catalogued sample loads, the buses exist,
## impacts take a voice, loops fade in and out, and a pour is voiced.

var _bench: Node3D
var _tick: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _moon: Vessel3D
var _beaker: Vessel3D
var _loop_peak: float = 0.0
var _pour_heard: bool = false


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main_bench.tscn") as PackedScene
	_bench = scene.instantiate() as Node3D
	root.add_child(_bench)
	_moon = _bench.get_node("Vessels/FlaskMoonwater") as Vessel3D
	_beaker = _bench.get_node("Vessels/Beaker") as Vessel3D


func _playing_voices(d: AudioDirector) -> int:
	var n: int = 0
	for v: AudioStreamPlayer3D in d._voices:
		if v.playing:
			n += 1
	return n


func _physics_process(_delta: float) -> bool:
	_tick += 1
	var d: AudioDirector = AudioDirector.instance
	if _tick == 30:
		_check(d != null and is_instance_valid(d) and d.is_inside_tree(), "the HUD starts the audio director")
		if d == null:
			_finish()
			return true
		var missing: PackedStringArray = PackedStringArray()
		for sound: StringName in AudioDirector.CATALOG:
			if (d._streams.get(sound, []) as Array).size() != int(AudioDirector.CATALOG[sound]):
				missing.append(String(sound))
		_check(missing.is_empty(), "every catalogued sound loads (missing: %s)" % ", ".join(missing))
		for bus: String in AudioDirector.BUSES:
			_check(AudioServer.get_bus_index(bus) >= 0, "bus %s exists" % bus)
		_check(AudioServer.get_bus_effect_count(AudioServer.get_bus_index("SFX")) == 1, "the SFX bus has its room reverb")
		_check(d._room.playing, "room tone is playing")
		var loop_stream: AudioStreamWAV = d._streams[&"pour_loop"][0] as AudioStreamWAV
		_check(loop_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop_stream.loop_end > 30000, "loop samples loop over their whole length")
		# Still settling: impacts stay quiet while the bench comes to rest.
		var before: int = _playing_voices(d)
		AudioDirector.impact(&"glass", 2.0, Vector3(0.0, 1.0, 0.0))
		_check(_playing_voices(d) == before, "impacts are muted while objects settle")
	if _tick == 120:
		var before2: int = _playing_voices(d)
		AudioDirector.contact(_moon, _beaker, 1.5, _moon.global_position)
		AudioDirector.impact(&"iron", 2.0, Vector3(3.0, 1.0, 0.0))
		_check(_playing_voices(d) >= before2 + 2, "a glass clink and an iron ring each take a voice")
		var again: int = _playing_voices(d)
		AudioDirector.impact(&"iron", 2.0, Vector3(3.0, 1.0, 0.0))
		_check(_playing_voices(d) == again, "the same sound cannot retrigger within a few milliseconds")
		AudioDirector.play_ui(&"ui_click")
		_check(d._ui_voices[(d._next_ui + AudioDirector.UI_VOICES - 1) % AudioDirector.UI_VOICES].playing, "interface sounds play on the UI voices")
		# Tip the moonwater flask over the beaker.
		_moon.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		_moon.freeze = true
		var tilt: Basis = Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(105.0))
		_moon.global_transform = Transform3D(tilt, _beaker.global_position + Vector3(0.0, 0.12, 0.0) - tilt.y * 0.07)
	if _tick > 120 and _tick < 200:
		AudioDirector.loop(&"test", &"crusher_loop", Vector3(3.0, 1.0, 0.0), 0.8)
		var lv: AudioDirector.LoopVoice = d._loops.get(&"test") as AudioDirector.LoopVoice
		if lv != null:
			_loop_peak = maxf(_loop_peak, lv.gain)
		var pour: AudioDirector.LoopVoice = d._loops.get(&"pour_a") as AudioDirector.LoopVoice
		if pour != null and pour.player.playing and pour.gain > 0.05:
			_pour_heard = true
	if _tick == 200:
		_check(_loop_peak > 0.6, "a driven loop fades in (peak gain %.2f)" % _loop_peak)
		_check(_pour_heard or not _moon.is_pouring, "pouring is voiced by a pour loop")
		_check(_moon.is_pouring or _moon.mixture.get_liquid_volume_m3() < 1e-6, "the flask is pouring for the test")
	if _tick == 290:
		var lv2: AudioDirector.LoopVoice = d._loops.get(&"test") as AudioDirector.LoopVoice
		_check(lv2 != null and not lv2.player.playing and lv2.gain == 0.0, "a loop fades out and stops once it is no longer driven")
		AudioDirector.set_volume("SFX", 0.5, false)
		_check(absf(AudioDirector.get_volume("SFX") - 0.5) < 0.01, "bus volume round-trips")
		AudioDirector.set_volume("SFX", 0.0, false)
		_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "zero volume mutes the bus")
		AudioDirector.set_volume("SFX", 1.0, false)
		_finish()
		return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("AUDIO SMOKE PASS")
		quit(0)
	else:
		for f: String in _failures:
			printerr("AUDIO SMOKE FAIL  " + f)
		quit(1)
