class_name Hammer3D
extends RigidBody3D
## Geologist's hammer, held head-down. While held, tap Space (or the Strike
## button) to slam it down onto whatever is below, or HOLD to wind up: the
## hammer rises higher the longer you hold, and on release it swings down with
## an extra downward impulse. The contact's kinetic energy (½ m v²) chips at a
## rock's hardness-scaled integrity until it cracks.
##
## Easy mode: a blow aimed near a rock always lands. Any rock within
## ASSIST_RADIUS of the head is the target; each strike takes at least a fixed
## share of its strength (more when charged), so even granite cracks in a
## handful of hits. Click while holding the hammer to strike.

const SLAM_SECONDS: float = 0.22
const MIN_STRIKE_SPEED: float = 0.8
const CHARGE_SECONDS: float = 0.8
const WINDUP_METERS: float = 0.16
## Downward swing impulse at full charge (N·s): an arm putting its back into it.
const SWING_IMPULSE_N_S: float = 2.2
const ASSIST_RADIUS_METERS: float = 0.14
## Share of a rock's strength each blow is guaranteed to take (soft -> hard).
const EASY_FRACTION_SOFT: float = 0.55
const EASY_FRACTION_HARD: float = 0.3

@export var head_mass_kg: float = 0.45
@export var bench_top_y: float = 0.8

var _slam_timer: float = 0.0
var _cooldown: float = 0.0
## 0..1 while winding up (read by the HUD charge meter).
var charge: float = 0.0
var charging: bool = false
var _swing_impulse: float = 0.0
var _target: Rock3D = null
var _target_hit_fraction: float = 0.0
var _swing_charge: float = 0.0


func _ready() -> void:
	collision_layer = SimConstants.LAYER_TACTILE_TOOL
	collision_mask = SimConstants.LAYER_STATIC_BENCH | SimConstants.LAYER_SOLID_REAGENT | SimConstants.LAYER_TACTILE_TOOL
	mass = head_mass_kg
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	var wood: StandardMaterial3D = PropMaterials.textured("wood", Color(0.62, 0.42, 0.24), 0.12)
	var iron: StandardMaterial3D = PropMaterials.textured("iron", Color(0.42, 0.42, 0.45), 0.08, 0.9)
	var handle: CylinderMesh = CylinderMesh.new()
	handle.top_radius = 0.009
	handle.bottom_radius = 0.011
	handle.height = 0.24
	handle.material = wood
	var handle_mi: MeshInstance3D = MeshInstance3D.new()
	handle_mi.mesh = handle
	handle_mi.position.y = 0.04
	add_child(handle_mi)
	var head: BoxMesh = BoxMesh.new()
	head.size = Vector3(0.11, 0.035, 0.035)
	head.material = iron
	var head_mi: MeshInstance3D = MeshInstance3D.new()
	head_mi.mesh = head
	head_mi.position.y = -0.085
	add_child(head_mi)
	# Chisel end: tapers from the head to a cutting edge.
	var pick_mi: MeshInstance3D = MeshInstance3D.new()
	pick_mi.mesh = _wedge_mesh(0.045, 0.014, 0.0012, 0.015)
	pick_mi.material_override = iron
	pick_mi.position = Vector3(0.05, -0.085, 0.0)
	add_child(pick_mi)
	_add_fittings(wood)
	var handle_shape: CapsuleShape3D = CapsuleShape3D.new()
	handle_shape.radius = 0.012
	handle_shape.height = 0.24
	var hs: CollisionShape3D = CollisionShape3D.new()
	hs.shape = handle_shape
	hs.position.y = 0.04
	add_child(hs)
	var head_shape: BoxShape3D = BoxShape3D.new()
	head_shape.size = head.size
	var hd: CollisionShape3D = CollisionShape3D.new()
	hd.shape = head_shape
	hd.position.y = -0.085
	add_child(hd)


## Finishing touches: a polished striking face, the steel wedge that locks the
## head on, a brass ferrule, a leather-wrapped grip and a rounded pommel.
func _add_fittings(wood: StandardMaterial3D) -> void:
	var steel: StandardMaterial3D = PropMaterials.textured("metal", Color(0.8, 0.81, 0.84), 0.08, 1.0)
	var brass: StandardMaterial3D = PropMaterials.textured("metal", Color(0.95, 0.72, 0.34), 0.08, 0.9)
	var leather: StandardMaterial3D = PropMaterials.textured("leather", Color(0.22, 0.13, 0.08), 0.06)
	var face: CylinderMesh = CylinderMesh.new()
	face.top_radius = 0.0205
	face.bottom_radius = 0.022
	face.height = 0.014
	face.radial_segments = 24
	face.material = steel
	var face_mi: MeshInstance3D = MeshInstance3D.new()
	face_mi.mesh = face
	face_mi.rotation.z = PI * 0.5  # crowned face points along -X
	face_mi.position = Vector3(-0.058, -0.085, 0.0)
	add_child(face_mi)
	var wedge: BoxMesh = BoxMesh.new()
	wedge.size = Vector3(0.016, 0.003, 0.004)
	wedge.material = steel
	var wedge_mi: MeshInstance3D = MeshInstance3D.new()
	wedge_mi.mesh = wedge
	wedge_mi.position = Vector3(0.0, -0.1035, 0.0)
	add_child(wedge_mi)
	var eye: CylinderMesh = CylinderMesh.new()
	eye.top_radius = 0.0115
	eye.bottom_radius = 0.0115
	eye.height = 0.004
	eye.material = wood
	var eye_mi: MeshInstance3D = MeshInstance3D.new()
	eye_mi.mesh = eye
	eye_mi.position = Vector3(0.0, -0.1025, 0.0)
	add_child(eye_mi)
	var ferrule: CylinderMesh = CylinderMesh.new()
	ferrule.top_radius = 0.0122
	ferrule.bottom_radius = 0.013
	ferrule.height = 0.012
	ferrule.material = brass
	var ferrule_mi: MeshInstance3D = MeshInstance3D.new()
	ferrule_mi.mesh = ferrule
	ferrule_mi.position = Vector3(0.0, -0.0615, 0.0)
	add_child(ferrule_mi)
	var grip: CylinderMesh = CylinderMesh.new()
	grip.top_radius = 0.0102
	grip.bottom_radius = 0.0108
	grip.height = 0.075
	grip.material = leather
	var grip_mi: MeshInstance3D = MeshInstance3D.new()
	grip_mi.mesh = grip
	grip_mi.position = Vector3(0.0, 0.112, 0.0)
	add_child(grip_mi)
	for ring_y: float in [0.073, 0.151]:
		var band: CylinderMesh = CylinderMesh.new()
		band.top_radius = 0.0112
		band.bottom_radius = 0.0112
		band.height = 0.003
		band.material = brass
		var band_mi: MeshInstance3D = MeshInstance3D.new()
		band_mi.mesh = band
		band_mi.position = Vector3(0.0, ring_y, 0.0)
		add_child(band_mi)
	var pommel: SphereMesh = SphereMesh.new()
	pommel.radius = 0.0115
	pommel.height = 0.016
	pommel.material = wood
	var pommel_mi: MeshInstance3D = MeshInstance3D.new()
	pommel_mi.mesh = pommel
	pommel_mi.position = Vector3(0.0, 0.161, 0.0)
	add_child(pommel_mi)


## Wedge from a (2*half_y by 2*half_z) base at x = 0 to an edge of height
## 2*tip_y at x = length. Faces have their own vertices (hard edges).
static func _wedge_mesh(length: float, half_y: float, tip_y: float, half_z: float) -> ArrayMesh:
	var b: Array[Vector3] = [Vector3(0.0, -half_y, -half_z), Vector3(0.0, half_y, -half_z), Vector3(0.0, half_y, half_z), Vector3(0.0, -half_y, half_z)]
	var t: Array[Vector3] = [Vector3(length, -tip_y, -half_z), Vector3(length, tip_y, -half_z), Vector3(length, tip_y, half_z), Vector3(length, -tip_y, half_z)]
	var quads: Array = [[b[0], b[1], b[2], b[3]], [t[0], t[1], t[2], t[3]], [b[1], t[1], t[2], b[2]], [b[0], t[0], t[3], b[3]], [b[0], b[1], t[1], t[0]], [b[3], b[2], t[2], t[3]]]
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()
	for q: Array in quads:
		var base: int = verts.size()
		for p: Vector3 in q:
			verts.append(p)
			uvs.append(Vector2(p.x, p.y + p.z))
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	return MeshUtil.finish(verts, idx, uvs, Vector3(length * 0.5, 0.0, 0.0), false)


func slam() -> void:
	if _cooldown <= 0.0:
		_slam_timer = SLAM_SECONDS
		_cooldown = SLAM_SECONDS + 0.15
		_start_swing(0.0)


## Second click while held: strike if there's a rock to hit (else drop it).
func click_use() -> bool:
	if find_target() == null:
		return false
	slam()
	return true


## Nearest crackable rock under / near the hammer head.
func find_target() -> Rock3D:
	if not is_inside_tree():
		return null
	var head: Vector3 = global_position
	var best: Rock3D = null
	var best_d: float = ASSIST_RADIUS_METERS
	for n: Node in get_tree().get_nodes_in_group(&"collectibles"):
		var r: Rock3D = n as Rock3D
		if r == null or r.mineral == null or r.mineral.kind == MineralData.Kind.SAND or r.cut != RockMeshes.Cut.NONE:
			continue
		var d: float = Vector2(r.global_position.x - head.x, r.global_position.z - head.z).length()
		if d < best_d and r.global_position.y < head.y + 0.05:
			best = r
			best_d = d
	return best


func _start_swing(with_charge: float) -> void:
	_target = find_target()
	_target_hit_fraction = 0.0
	_swing_charge = with_charge
	AudioDirector.play(&"hammer_swing", global_position, lerpf(-12.0, -5.0, clampf(with_charge, 0.0, 1.0)), lerpf(1.1, 0.85, clampf(with_charge, 0.0, 1.0)))


## Guaranteed share of the target's strength for this blow.
func easy_fraction(m: MineralData, with_charge: float) -> float:
	var hard: float = clampf((m.hardness_mohs - 2.0) / 6.0, 0.0, 1.0)
	return lerpf(EASY_FRACTION_SOFT, EASY_FRACTION_HARD, hard) * (1.0 + with_charge)


## Start winding up a charged blow (Space / Strike held).
func begin_charge() -> void:
	if _cooldown <= 0.0:
		charging = true
		charge = 0.0


## Let go: swing down with power proportional to the wind-up.
func release_charge() -> void:
	if not charging:
		return
	charging = false
	_slam_timer = SLAM_SECONDS
	_cooldown = SLAM_SECONDS + 0.15
	_swing_impulse = SWING_IMPULSE_N_S * charge * charge
	_start_swing(charge)


var _seam_rock: Rock3D = null


func _physics_process(delta: float) -> void:
	# While held, the rock it would hit shows its glowing weak seam.
	var aim: Rock3D = find_target() if TactileGrabber3D.current_held == self else null
	if aim != _seam_rock:
		if _seam_rock != null and is_instance_valid(_seam_rock):
			_seam_rock.show_seam(false)
		_seam_rock = aim
	if _seam_rock != null and is_instance_valid(_seam_rock):
		_seam_rock.show_seam(true)
	var was_slamming: bool = _slam_timer > 0.0
	_slam_timer = maxf(_slam_timer - delta, 0.0)
	if was_slamming and _slam_timer <= 0.0:
		_finish_swing()
	_cooldown = maxf(_cooldown - delta, 0.0)
	if charging:
		charge = minf(charge + delta / CHARGE_SECONDS, 1.0)
	elif _slam_timer <= 0.0:
		charge = 0.0
	if _swing_impulse > 0.0:
		apply_central_impulse(Vector3.DOWN * _swing_impulse)
		_swing_impulse = 0.0


## While slamming, pull the head down to the bench top; while winding up,
## lift it higher the longer the charge.
func get_hover_override_y() -> float:
	if _slam_timer > 0.0:
		return bench_top_y + 0.1
	if charging:
		return bench_top_y + 0.22 + WINDUP_METERS * charge
	return NAN


func _on_body_entered(body: Node) -> void:
	var rock: Rock3D = body as Rock3D
	if rock == null:
		AudioDirector.contact(self, body, linear_velocity.length(), global_position, 0.9)
		return
	var v_rel: float = (linear_velocity - rock.linear_velocity).length()
	AudioDirector.impact(&"iron", v_rel, global_position, 0.9, -6.0)
	if rock == _target and _slam_timer > 0.0:
		_finish_swing()
		return
	if v_rel >= MIN_STRIKE_SPEED:
		rock.strike(0.5 * head_mass_kg * v_rel * v_rel)


## Land the blow on the target (once per swing): the guaranteed share of its
## strength, so aiming close enough is all it takes.
func _finish_swing() -> void:
	var t: Rock3D = _target
	_target = null
	if t == null or not is_instance_valid(t) or t.mineral == null:
		return
	if t.seam_hit(global_position.x):
		t.critical_crack()
		return
	t.strike_fraction(easy_fraction(t.mineral, _swing_charge))
