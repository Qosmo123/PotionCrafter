class_name MachineIntake
extends Area3D
## A wide catch zone above a machine's hopper (rock crusher, sand sifter).
## Anything it accepts that is let go over it is guided into the hopper, so
## the player only has to drop it roughly above the machine. While a fitting
## item is carried, a glowing marker shows where to drop it.

static var all_intakes: Array[MachineIntake] = []

## Shown in the hint line: "Click to drop it into the <machine_name>".
var machine_name: String = "machine"
## Where caught items are placed (world space is computed from this local point).
var drop_local: Vector3 = Vector3.ZERO
## Returns true for items this machine takes (set by the machine).
var accepts: Callable = Callable()
## Optional: called with each caught item instead of placing it in the
## hopper (the storage cabinet puts items away).
var on_catch: Callable = Callable()
## What the machine takes, for the refusal hint ("rough rocks"). Things it
## doesn't take that end up in the zone are nudged back out.
var wants: String = ""
## Optional: marker text for the carried item (the trader's scale shows the
## price). Called with the carried body; "" keeps "drop it here".
var marker_text: Callable = Callable()
## How far (left/right) from the drop point a carried item still counts as
## "over" this intake. Small for intakes squeezed between other targets.
var catch_dx_meters: float = 0.13
## Optional hand hint while carrying over it ("Click to set it on the ...").
var drop_note: String = ""

var _marker: MeshInstance3D
var _marker_label: Label3D
var _time: float = 0.0
var _active: float = 0.0  # 0 hidden, 0.5 carrying something that fits, 1 over it


## Build a catch zone of `size` centred `center` (local to `machine`).
static func make(machine: Node3D, name_: String, size: Vector3, center: Vector3, drop_at: Vector3, accept: Callable) -> MachineIntake:
	var intake: MachineIntake = MachineIntake.new()
	intake.machine_name = name_
	intake.drop_local = drop_at - center
	intake.accepts = accept
	intake.position = center
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	var cs: CollisionShape3D = CollisionShape3D.new()
	cs.shape = box
	intake.add_child(cs)
	machine.add_child(intake)
	return intake


func _ready() -> void:
	collision_layer = 0
	collision_mask = SimConstants.LAYER_SOLID_REAGENT | SimConstants.LAYER_RIGID_VESSEL | SimConstants.LAYER_TACTILE_TOOL
	monitorable = false
	all_intakes.append(self)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.11, 0.11)
	quad.material = VesselEffects.billboard_material(true, 1.8, Color(1.0, 0.82, 0.42))
	_marker = MeshInstance3D.new()
	_marker.mesh = quad
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	_marker.position = drop_local + Vector3(0.0, 0.15, 0.1)
	add_child(_marker)
	var pill: WorldPill = ClickSwitch.make_caption(self, _marker.position + Vector3(0.0, 0.055, 0.0))
	pill.auto_hide = false  # shown while a fitting item is carried
	_marker_label = pill
	_marker_label.text = "drop it here"
	_marker_label.modulate = Color(1.0, 0.85, 0.5)
	_marker_label.visible = false


func _exit_tree() -> void:
	all_intakes.erase(self)


func drop_world() -> Vector3:
	return global_transform * drop_local


func takes(body: Node) -> bool:
	return accepts.is_valid() and bool(accepts.call(body))


## Take an item that was let go over the machine.
func receive(body: RigidBody3D) -> void:
	if body.is_queued_for_deletion():
		return  # already taken this frame
	if on_catch.is_valid():
		on_catch.call(body)
		return
	body.global_position = drop_world()
	body.linear_velocity = Vector3(0.0, -0.2, 0.0)
	body.angular_velocity = Vector3.ZERO


## The intake a carried item at `x` would drop into (left/right only), or null.
static func under(body: Node, x: float) -> MachineIntake:
	var best: MachineIntake = null
	var best_d: float = 1e9
	for intake: MachineIntake in all_intakes:
		if not intake.is_inside_tree() or not intake.takes(body):
			continue
		var d: float = absf(intake.drop_world().x - x)
		if d < intake.catch_dx_meters and d < best_d:
			best = intake
			best_d = d
	return best


## The intake under a carried `body` that won't take it (for a hint), or null.
static func refusing(body: Node, x: float) -> MachineIntake:
	for intake: MachineIntake in all_intakes:
		if not intake.is_inside_tree() or intake.wants == "" or intake.takes(body) or body is MachineHandle3D:
			continue
		if absf(intake.drop_world().x - x) < 0.1:
			return intake
	return null


## Push something the machine doesn't take back out of its hopper, sideways
## toward the player, and say what the machine is for (once per item).
func _refuse(rb: RigidBody3D) -> void:
	var now: int = Time.get_ticks_msec()
	if now - int(rb.get_meta(&"intake_refused_ms", -100000)) < 1200:
		return
	rb.set_meta(&"intake_refused_ms", now)
	var side: float = signf(rb.global_position.x - drop_world().x)
	if side == 0.0:
		side = 1.0
	rb.linear_velocity = Vector3(side * 0.9, 1.1, 0.25)
	if not rb.has_meta(&"intake_refused_told") and GrimoireJournal.instance != null:
		rb.set_meta(&"intake_refused_told", true)
		GrimoireJournal.instance.toast.emit("The %s only takes %s" % [machine_name, wants], &"warning")


## Show markers for a carried `body` (null hides them); `chosen` pulses.
static func update_markers(body: Node, chosen: MachineIntake) -> void:
	for intake: MachineIntake in all_intakes:
		intake._active = 0.0 if body == null or not intake.takes(body) else (1.0 if intake == chosen else 0.5)
		if intake._active > 0.0 and intake.marker_text.is_valid():
			var text: String = String(intake.marker_text.call(body))
			intake._marker_label.text = text if text != "" else "drop it here"


func _physics_process(delta: float) -> void:
	_time += delta
	_marker.visible = _active > 0.0
	_marker_label.visible = _active > 0.0
	if _marker.visible:
		var pulse: float = 0.5 + 0.5 * sin(_time * 6.0)
		_marker.transparency = lerpf(0.2, 0.0, pulse) if _active > 0.9 else 0.3
		_marker.scale = Vector3.ONE * (1.2 + 0.2 * pulse if _active > 0.9 else 0.85)
	# Guide anything let go over the machine into the hopper.
	for body: Node3D in get_overlapping_bodies():
		var rb: RigidBody3D = body as RigidBody3D
		if rb == null or rb == TactileGrabber3D.current_held or rb.freeze:
			continue
		if not takes(rb):
			# Never the machine's own parts (crank handle, shaker).
			if wants != "" and rb.global_position.y < global_position.y and not rb is MachineHandle3D and not get_parent().is_ancestor_of(rb):
				_refuse(rb)
			continue
		if not on_catch.is_valid() and rb.global_position.distance_to(drop_world()) < 0.03:
			continue
		receive(rb)
