class_name AudioDirector
extends Node
## The game's sound system. Every sound is a synthesised sample from
## content/audio (tools/gen_audio.py); this node decides what plays, where,
## how loud and at what pitch.
##
## - One-shots: `play(name, position)` from a pool of 3D voices (round-robin,
##   never allocating during play). Names with numbered variants pick one at
##   random, with a small random pitch drift so repeats never sound identical.
## - Impacts: `contact(body, other, speed, position)` maps the two materials'
##   resonances (glass, ceramic, iron, wood, stone, crystal, soft) and the
##   relative speed to sample, loudness and pitch.
## - Loops: `loop(key, name, position, gain, pitch)` is called every tick by
##   whatever is making the noise (a crank, a wheel, a stirring rod); the loop
##   fades in, follows gain and pitch, and fades out once the calls stop.
## - Vessels: pouring, boiling, fizzing, burning and arcane hum are found by
##   scanning Vessel3D.all_vessels each frame and voiced for the loudest few.
## - Interface: every button clicks and hovers; journal toasts chime by kind.
## - Ambience: a room-tone bed plus occasional gusts, drips and creaks.
## - Buses: SFX (with a little stone-room reverb), Ambience and UI under
##   Master (limited). Volumes persist in user://settings.cfg.
##
## All entry points are static and safe to call from anywhere, including
## headless tests with no scene (they do nothing there).

const AUDIO_DIR: String = "res://content/audio/"
const SETTINGS_PATH: String = "user://settings.cfg"
const VOICES: int = 24
const UI_VOICES: int = 6
## Number of variants per sound (1 = a single file with no numeric suffix).
const CATALOG: Dictionary = {
	&"impact_glass": 4, &"impact_ceramic": 2, &"impact_iron": 3, &"impact_wood": 3, &"impact_stone": 3,
	&"impact_crystal": 3, &"impact_soft": 2,
	&"glass_ting": 3, &"glass_scrape_loop": 1, &"cork_pop": 1, &"cork_push": 1, &"wax_pour": 1, &"wax_crack": 1, &"stamp": 1,
	&"pour_loop": 1, &"pour_thick_loop": 1, &"boil_loop": 1, &"fizz_loop": 1, &"swirl_loop": 1, &"drip": 3, &"splash": 2,
	&"fire_loop": 1, &"candle_loop": 1, &"ignite": 1, &"explosion": 1, &"glass_shatter": 1,
	&"arcane_loop": 1, &"arcane_chime": 2, &"spell_cast": 1,
	&"hammer_swing": 1, &"rock_hit": 3, &"rock_crack": 2, &"gem_reveal": 1, &"crusher_loop": 1, &"sifter_loop": 1,
	&"wheel_loop": 1, &"grind_loop": 1, &"chalk_loop": 1, &"sand_pour": 1, &"powder_pour_loop": 1,
	&"click": 2, &"switch": 1, &"ratchet": 1, &"hotplate_loop": 1,
	&"ui_hover": 1, &"ui_click": 1, &"ui_open": 1, &"ui_close": 1, &"page_turn": 1, &"ui_toast": 1, &"ui_error": 1,
	&"discover": 1, &"coin": 1, &"whoosh": 1, &"grab": 1,
	&"room_loop": 1, &"wind_gust": 1, &"distant_drip": 1, &"wood_creak": 2,
}
const BUSES: PackedStringArray = ["Master", "SFX", "Ambience", "UI"]
const DEFAULT_VOLUMES: Dictionary = {"Master": 0.9, "SFX": 1.0, "Ambience": 0.7, "UI": 0.8}
## Slowest contact that makes a sound, and the speed that plays at full level.
const MIN_IMPACT_SPEED_M_S: float = 0.12
const FULL_IMPACT_SPEED_M_S: float = 3.0
## Shortest gap between two plays of the same sound (stops machine-gunning).
const REPEAT_GAP_MSEC: int = 45
## Objects settle onto the bench when the scene loads; stay quiet meanwhile.
const SETTLE_SECONDS: float = 1.5

static var instance: AudioDirector = null
static var _pending: bool = false

var _streams: Dictionary = {}  # StringName -> Array[AudioStream]
var _last_play_msec: Dictionary = {}  # StringName -> int
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0
var _ui_voices: Array[AudioStreamPlayer] = []
var _next_ui: int = 0
var _loops: Dictionary = {}  # StringName -> LoopVoice
var _room: AudioStreamPlayer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _age_s: float = 0.0
var _ambient_timer_s: float = 12.0
var _journal_hooked: bool = false


class LoopVoice extends RefCounted:
	var player: AudioStreamPlayer3D
	var sound: StringName
	var target: float = 0.0
	var gain: float = 0.0
	var pitch: float = 1.0
	var hold_s: float = 0.0
	var fresh: bool = false
	var base_db: float = 0.0


# --- Static entry points -----------------------------------------------------------

## Play a one-shot at a world position.
static func play(sound: StringName, at: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var d: AudioDirector = _director()
	if d != null:
		d._play_3d(sound, at, volume_db, pitch)


## Play a non-positional interface sound.
static func play_ui(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var d: AudioDirector = _director()
	if d != null:
		d._play_ui(sound, volume_db, pitch)


## A struck `material` at `speed_m_s`. `pitch` scales with the object's size.
static func impact(material: StringName, speed_m_s: float, at: Vector3, pitch: float = 1.0, trim_db: float = 0.0) -> void:
	if speed_m_s < MIN_IMPACT_SPEED_M_S:
		return
	var d: AudioDirector = _director()
	if d == null or d._age_s < SETTLE_SECONDS:
		return
	d._play_3d(impact_sound(material), at, impact_gain_db(speed_m_s) + trim_db, pitch)


## Two bodies meeting: the moving body's material rings, and the other one
## answers more quietly if it is made of something else.
static func contact(body: Node, other: Node, speed_m_s: float, at: Vector3, pitch: float = 1.0) -> void:
	if speed_m_s < MIN_IMPACT_SPEED_M_S:
		return
	var a: StringName = material_of(body)
	var b: StringName = material_of(other)
	impact(a, speed_m_s, at, pitch)
	if b != a:
		impact(b, speed_m_s, at, 1.0, -7.0)


## Keep a continuous sound alive. Call every tick while it should be heard;
## it fades out by itself shortly after the calls stop. `gain` is 0..1.
static func loop(key: StringName, sound: StringName, at: Vector3, gain: float, pitch: float = 1.0, base_db: float = 0.0) -> void:
	if gain <= 0.001:
		return
	var d: AudioDirector = _director()
	if d != null:
		d._drive_loop(key, sound, at, gain, pitch, base_db)


## Loudness for a contact at this speed: silent below the threshold, rising
## quickly at first (a gentle set-down is audible) and flattening toward 0 dB.
static func impact_gain_db(speed_m_s: float) -> float:
	var f: float = clampf((speed_m_s - MIN_IMPACT_SPEED_M_S) / (FULL_IMPACT_SPEED_M_S - MIN_IMPACT_SPEED_M_S), 0.0, 1.0)
	return lerpf(-30.0, 0.0, pow(f, 0.45))


static func impact_sound(material: StringName) -> StringName:
	match material:
		&"glass": return &"impact_glass"
		&"ceramic": return &"impact_ceramic"
		&"iron": return &"impact_iron"
		&"stone": return &"impact_stone"
		&"crystal": return &"impact_crystal"
		&"soft": return &"impact_soft"
	return &"impact_wood"


## What a body sounds like when struck. Scripts can override with
## `set_meta("sound_material", &"iron")`; otherwise it follows the type.
static func material_of(node: Node) -> StringName:
	if node == null:
		return &"wood"
	if node.has_meta(&"sound_material"):
		return node.get_meta(&"sound_material") as StringName
	if node is Vessel3D:
		return &"glass"
	if node is Rock3D:
		var m: MineralData = (node as Rock3D).mineral
		if m != null and m.kind == MineralData.Kind.SAND:
			return &"soft"
		return &"crystal" if m != null and (m.kind == MineralData.Kind.GEM or (node as Rock3D).cut != RockMeshes.Cut.NONE) else &"stone"
	if node is Hammer3D or node is HotPlate3D:
		return &"iron"
	if node is Berry3D:
		return &"soft"
	if node is StirTool3D:
		return &"glass"
	return &"wood"


## Smaller vessels ring higher, and liquid inside lowers and deadens the note.
static func vessel_pitch(outer_radius_meters: float, fill_fraction: float) -> float:
	return clampf(0.034 / maxf(outer_radius_meters, 0.005), 0.72, 1.45) * (1.0 - 0.28 * clampf(fill_fraction, 0.0, 1.0))


static func set_volume(bus: String, linear: float, persist: bool = true) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(index, linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.001)))
	if persist:
		var cfg: ConfigFile = ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("audio", bus, linear)
		cfg.save(SETTINGS_PATH)


static func get_volume(bus: String) -> float:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		return float(DEFAULT_VOLUMES.get(bus, 1.0))
	return 0.0 if AudioServer.is_bus_mute(index) else db_to_linear(AudioServer.get_bus_volume_db(index))


## Start the sound system now (room tone, button sounds) rather than at the
## first sound. Called by the HUD when the bench loads.
static func ensure() -> void:
	_director()


static func _director() -> AudioDirector:
	if instance != null and is_instance_valid(instance) and instance.is_inside_tree():
		return instance
	if _pending:
		return null
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	_pending = true
	instance = AudioDirector.new()
	instance.name = "AudioDirector"
	tree.root.add_child.call_deferred(instance)
	return null


# --- Setup ----------------------------------------------------------------------------

func _ready() -> void:
	_pending = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_setup_buses()
	for sound: StringName in CATALOG:
		var count: int = CATALOG[sound]
		var list: Array[AudioStream] = []
		for v: int in count:
			var path: String = AUDIO_DIR + String(sound) + ("" if count == 1 else "_%d" % (v + 1)) + ".wav"
			var stream: AudioStreamWAV = load(path) as AudioStreamWAV
			if stream == null:
				push_warning("AudioDirector: missing %s (run tools/gen_audio.py)" % path)
				continue
			if String(sound).ends_with("_loop"):
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_begin = 0
				stream.loop_end = int(stream.get_length() * float(stream.mix_rate))
			list.append(stream)
		_streams[sound] = list
		_last_play_msec[sound] = -1000
	for i: int in VOICES:
		var p: AudioStreamPlayer3D = _make_3d(&"SFX")
		_voices.append(p)
	for i: int in UI_VOICES:
		var u: AudioStreamPlayer = AudioStreamPlayer.new()
		u.bus = &"UI"
		add_child(u)
		_ui_voices.append(u)
	_room = AudioStreamPlayer.new()
	_room.bus = &"Ambience"
	_room.volume_db = -15.0
	add_child(_room)
	var room: Array = _streams.get(&"room_loop", [])
	if not room.is_empty():
		_room.stream = room[0]
		_room.play()
	get_tree().node_added.connect(_on_node_added)
	for node: Node in get_tree().root.find_children("*", "BaseButton", true, false):
		_hook_button(node as BaseButton)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _make_3d(bus: StringName) -> AudioStreamPlayer3D:
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.bus = bus
	# The side-view camera sits ~3 m from the bench: keep everything on screen
	# near full level, let the other stations fall away, and pan by position.
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = 5.0
	p.max_db = 2.0
	p.max_distance = 14.0
	p.panning_strength = 1.4
	p.attenuation_filter_cutoff_hz = 20500.0
	add_child(p)
	return p


func _setup_buses() -> void:
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, &"Master")
			if bus == "SFX":
				# A small stone room: short, dark tail.
				var verb: AudioEffectReverb = AudioEffectReverb.new()
				verb.room_size = 0.38
				verb.damping = 0.65
				verb.spread = 0.8
				verb.hipass = 0.25
				verb.dry = 1.0
				verb.wet = 0.11
				AudioServer.add_bus_effect(index, verb)
	if AudioServer.get_bus_effect_count(0) == 0:
		var limiter: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(0, limiter)
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for bus: String in BUSES:
		set_volume(bus, float(cfg.get_value("audio", bus, DEFAULT_VOLUMES[bus])), false)


# --- One-shots ------------------------------------------------------------------------

func _pick(sound: StringName) -> AudioStream:
	var list: Array = _streams.get(sound, [])
	if list.is_empty():
		return null
	var now: int = Time.get_ticks_msec()
	if now - int(_last_play_msec[sound]) < REPEAT_GAP_MSEC:
		return null
	_last_play_msec[sound] = now
	return list[_rng.randi_range(0, list.size() - 1)] as AudioStream


func _play_3d(sound: StringName, at: Vector3, volume_db: float, pitch: float) -> void:
	var stream: AudioStream = _pick(sound)
	if stream == null:
		return
	var voice: AudioStreamPlayer3D = null
	for i: int in VOICES:
		var candidate: AudioStreamPlayer3D = _voices[(_next_voice + i) % VOICES]
		if not candidate.playing:
			voice = candidate
			_next_voice = (_next_voice + i + 1) % VOICES
			break
	if voice == null:  # all busy: steal the oldest
		voice = _voices[_next_voice]
		_next_voice = (_next_voice + 1) % VOICES
	voice.stream = stream
	voice.global_position = at
	voice.volume_db = volume_db
	voice.pitch_scale = clampf(pitch * _rng.randf_range(0.96, 1.04), 0.25, 4.0)
	voice.play()


func _play_ui(sound: StringName, volume_db: float, pitch: float) -> void:
	var stream: AudioStream = _pick(sound)
	if stream == null:
		return
	var voice: AudioStreamPlayer = _ui_voices[_next_ui]
	_next_ui = (_next_ui + 1) % UI_VOICES
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = clampf(pitch, 0.25, 4.0)
	voice.play()


# --- Loops ----------------------------------------------------------------------------

func _drive_loop(key: StringName, sound: StringName, at: Vector3, gain: float, pitch: float, base_db: float) -> void:
	var lv: LoopVoice = _loops.get(key) as LoopVoice
	if lv == null:
		lv = LoopVoice.new()
		lv.player = _make_3d(&"Ambience" if key == &"candle" else &"SFX")
		_loops[key] = lv
	if lv.sound != sound:
		var list: Array = _streams.get(sound, [])
		if list.is_empty():
			return
		lv.sound = sound
		lv.player.stream = list[0]
		if lv.player.playing:
			lv.player.play(_rng.randf() * lv.player.stream.get_length())
	lv.target = clampf(gain, 0.0, 1.0)
	lv.pitch = pitch
	lv.base_db = base_db
	lv.hold_s = 0.12
	lv.fresh = true
	lv.player.global_position = at


func _update_loops(delta: float) -> void:
	for key: StringName in _loops:
		var lv: LoopVoice = _loops[key]
		# A loop driven since the last frame stays alive however long that
		# frame took; otherwise it expires shortly after the calls stop.
		if lv.fresh:
			lv.fresh = false
		else:
			lv.hold_s -= delta
			if lv.hold_s <= 0.0:
				lv.target = 0.0
		var rate: float = 14.0 if lv.target > lv.gain else 5.0
		lv.gain = lerpf(lv.gain, lv.target, 1.0 - exp(-rate * delta))
		if lv.gain < 0.004 and lv.target <= 0.0:
			if lv.player.playing:
				lv.player.stop()
			lv.gain = 0.0
			continue
		if not lv.player.playing and lv.player.stream != null:
			lv.player.play(_rng.randf() * lv.player.stream.get_length())
		lv.player.volume_db = linear_to_db(maxf(lv.gain, 0.0005)) + lv.base_db
		lv.player.pitch_scale = lerpf(lv.player.pitch_scale, clampf(lv.pitch, 0.25, 4.0), 1.0 - exp(-10.0 * delta))


# --- Vessels: pour, boil, fizz, fire, arcane ---------------------------------------------

## Two loudest pourers, boilers and fires, and the single loudest fizz and
## arcane glow, each get a loop voice at the vessel's rim.
func _scan_vessels() -> void:
	var pour_a: Vessel3D = null
	var pour_b: Vessel3D = null
	var pour_ga: float = 0.0
	var pour_gb: float = 0.0
	var boil_a: Vessel3D = null
	var boil_ga: float = 0.0
	var fire_a: Vessel3D = null
	var fire_b: Vessel3D = null
	var fizz_a: Vessel3D = null
	var fizz_ga: float = 0.0
	var arcane_a: Vessel3D = null
	var arcane_ga: float = 0.0
	for v: Vessel3D in Vessel3D.all_vessels:
		if v.mixture == null or not v.is_inside_tree():
			continue
		var m: MixtureContainer = v.mixture
		if v.is_pouring:
			var g: float = pour_gain(v.pour_rate_m3_s)
			if g > pour_ga:
				pour_b = pour_a
				pour_gb = pour_ga
				pour_a = v
				pour_ga = g
			elif g > pour_gb:
				pour_b = v
				pour_gb = g
		if v.is_boiling:
			var gb: float = clampf(0.35 + m.get_liquid_volume_m3() / 4e-4, 0.35, 1.0)
			if gb > boil_ga:
				boil_a = v
				boil_ga = gb
		if m.burning:
			if fire_a == null:
				fire_a = v
			elif fire_b == null:
				fire_b = v
		if not v.sealed:
			var gf: float = clampf(m.gas_generation_mol_s / 0.02, 0.0, 1.0)
			if gf > fizz_ga and not v.is_boiling:
				fizz_a = v
				fizz_ga = gf
		var ga: float = clampf(m.arcane_flash * 1.5, 0.0, 1.0)
		if ga > arcane_ga:
			arcane_a = v
			arcane_ga = ga
	if pour_a != null:
		_vessel_pour(&"pour_a", pour_a, pour_ga)
	if pour_b != null:
		_vessel_pour(&"pour_b", pour_b, pour_gb)
	if boil_a != null:
		var vol_l: float = boil_a.mixture.get_liquid_volume_m3() * 1000.0
		_drive_loop(&"boil", &"boil_loop", _rim(boil_a), boil_ga, clampf(1.25 - vol_l * 0.9, 0.8, 1.25), -4.0)
	if fire_a != null:
		_drive_loop(&"fire_a", &"fire_loop", _rim(fire_a), 0.9, 1.0, -3.0)
	if fire_b != null:
		_drive_loop(&"fire_b", &"fire_loop", _rim(fire_b), 0.8, 1.12, -3.0)
	if fizz_a != null and fizz_ga > 0.02:
		_drive_loop(&"fizz", &"fizz_loop", _rim(fizz_a), sqrt(fizz_ga), 1.0, -8.0)
	if arcane_a != null and arcane_ga > 0.03:
		_drive_loop(&"arcane", &"arcane_loop", _rim(arcane_a), arcane_ga, 1.0, -12.0)


func _vessel_pour(key: StringName, v: Vessel3D, gain: float) -> void:
	if v.granular:
		_drive_loop(key, &"powder_pour_loop", _rim(v), clampf(gain * 1.3, 0.25, 1.0), 1.0, -9.0)
		return
	var visc: float = v.mixture.get_liquid_viscosity_pas()
	var thick: bool = visc > 0.4
	# Thin liquids hiss a little higher when the stream is fast.
	var pitch: float = clampf(1.15 - visc * 0.5, 0.75, 1.15) if not thick else clampf(1.1 - log(visc + 1.0) * 0.12, 0.7, 1.1)
	_drive_loop(key, &"pour_thick_loop" if thick else &"pour_loop", _rim(v), gain, pitch, -5.0)


## 0..1 loudness of a pour: 20 mL/s is a solid pour, a dribble is quiet.
static func pour_gain(rate_m3_s: float) -> float:
	return clampf(sqrt(maxf(rate_m3_s, 0.0) / 2.5e-5), 0.12, 1.0)


func _rim(v: Vessel3D) -> Vector3:
	return v.global_transform * Vector3(0.0, v.get_lip_local_y(), 0.0)


# --- Interface and ambience -----------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node as BaseButton)


func _hook_button(button: BaseButton) -> void:
	if button.has_meta(&"audio_hooked"):
		return
	button.set_meta(&"audio_hooked", true)
	button.pressed.connect(_on_button_pressed)
	button.mouse_entered.connect(_on_button_hover.bind(button))


func _on_button_pressed() -> void:
	_play_ui(&"ui_click", -8.0, 1.0)


func _on_button_hover(button: BaseButton) -> void:
	if not button.disabled and button.is_visible_in_tree():
		_play_ui(&"ui_hover", -22.0, 1.0)


func _on_toast(_text: String, kind: StringName) -> void:
	match kind:
		&"discovery", &"secret":
			_play_ui(&"discover", -6.0, 1.0)
		&"coins":
			_play_ui(&"coin", -8.0, 1.0)
		&"warning", &"danger":
			_play_ui(&"ui_error", -8.0, 1.0)
		_:
			_play_ui(&"ui_toast", -14.0, 1.0)


func _process(delta: float) -> void:
	_age_s += delta
	if not _journal_hooked and GrimoireJournal.instance != null:
		_journal_hooked = true
		GrimoireJournal.instance.toast.connect(_on_toast)
	if _age_s > SETTLE_SECONDS:
		_scan_vessels()
	_update_loops(delta)
	_ambient_timer_s -= delta
	if _ambient_timer_s <= 0.0:
		_ambient_timer_s = _rng.randf_range(11.0, 28.0)
		_ambient_event()


## An occasional far-off sound somewhere around the room.
func _ambient_event() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var where: Vector3 = cam.global_position + Vector3(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-0.5, 1.5), -4.0)
	var roll: float = _rng.randf()
	var sound: StringName = &"wind_gust" if roll < 0.4 else (&"distant_drip" if roll < 0.7 else &"wood_creak")
	var stream: AudioStream = _pick(sound)
	if stream == null:
		return
	var voice: AudioStreamPlayer3D = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	voice.stream = stream
	voice.global_position = where
	voice.volume_db = _rng.randf_range(-16.0, -10.0)
	voice.pitch_scale = _rng.randf_range(0.9, 1.1)
	voice.play()
