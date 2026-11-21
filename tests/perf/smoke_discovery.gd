extends SceneTree
## Smoke test for discovery mode and the Mineral Lab satchel rules:
##   Kit          the bench is cleared to the starter kit; the stove is hidden.
##   Locks        an unknown reagent is locked in the satchel, with a hint
##                worked out from the data (malachite, vinegar).
##   Discovery    malachite powder + vinegar in the beaker forms blue
##                vitriol; it is learned and its stock bottle unlocks.
##   Equipment    the first discoveries bring the stove back.
##   Station      at the Mineral Lab a reagent can't be taken out, a rock
##                can, and it goes straight into the hand.
##   Refusal      a vessel let go over the crusher hopper is pushed back out.
## Usage: godot --path . --resolution 1280x720 --script res://tests/perf/smoke_discovery.gd

var _bench: Node3D
var _dp: DiscoveryProgress
var _store: InventoryStore
var _grabber: TactileGrabber3D
var _camera: LabCamera3D
var _failures: int = 0
var _step: int = 0
var _t: int = 0
var _beaker: Vessel3D
var _vessel: Vessel3D


func _initialize() -> void:
	_bench = (load("res://scenes/main_bench.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_bench)
	_grabber = _bench.get_node("Grabber") as TactileGrabber3D
	_camera = _bench.get_node("Camera3D") as LabCamera3D
	_store = _bench.get_node("InventoryStore") as InventoryStore


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _next() -> void:
	_step += 1
	_t = 0


func _item(id: String) -> Dictionary:
	return _store.find_item(id)


func _physics_process(_d: float) -> bool:
	_t += 1
	match _step:
		0:
			if _t == 20:
				_dp = DiscoveryProgress.instance
				_check(_dp != null, "discovery progress exists")
				_dp.persist = false
				_dp.active = true
				_dp.known.clear()
				for id: String in DiscoveryProgress.STARTER_SUBSTANCES:
					_dp.known[id] = true
				_dp._apply_starter_kit()
			if _t == 40:
				var names: PackedStringArray = []
				for v: Node in _bench.get_node("Vessels").get_children():
					if not v.is_queued_for_deletion():
						names.append(v.name)
				_check(names.size() == DiscoveryProgress.STARTER_VESSELS.size(), "bench cleared to the starter kit (%s)" % ", ".join(names))
				_check(not (_bench.get_node("HotPlate") as Node3D).visible, "stove hidden until earned")
				_beaker = _bench.get_node("Vessels/Beaker") as Vessel3D
				var vitriol: Dictionary = _item("reagent:Blue Vitriol")
				var lock: Dictionary = _store.discovery_lock(vitriol)
				_check(lock["locked"], "blue vitriol locked")
				_check(String(lock["hint"]).to_lower().contains("vinegar"), "hint worked out from the data: %s" % lock["hint"])
				_check(_store.take("reagent:Blue Vitriol") == null, "locked reagent can't be taken")
				_check(not _store.discovery_lock(_item("reagent:Vinegar"))["locked"], "vinegar is a starter")
				_beaker.mixture.clear()
				_beaker.mixture.add_substance(SubstanceRegistry.index_of_id(&"water"), 4.0, 293.15)
				_beaker.mixture.add_substance(SubstanceRegistry.index_of_id(&"acetic_acid"), 1.0, 293.15)
				_beaker.mixture.add_substance(SubstanceRegistry.index_of_id(&"malachite_powder"), 0.05, 293.15)
				_next()
		1:
			if _dp.is_known(&"copper_sulfate") or _t > 900:
				_check(_dp.is_known(&"copper_sulfate"), "blue vitriol discovered by experiment (%.1f s)" % (_t / 60.0))
				_check(not _store.discovery_lock(_item("reagent:Blue Vitriol"))["locked"], "its stock bottle unlocked")
				_check((_bench.get_node("HotPlate") as Node3D).visible, "stove earned after %d discoveries" % _dp.discovered_count())
				_camera.go_to_station(1)
				_next()
		2:
			if _t == 60:
				_check(_store.take_to_hand("reagent:Vinegar") == null, "Mineral Lab refuses reagents: " + _store.last_message)
				var rock: RigidBody3D = _store.take_to_hand("rock:granite")
				_check(rock != null and _grabber.held_body == rock, "a rock from the satchel goes into the hand")
				if rock != null:
					_store.stash(rock)
					_grabber.release()
				_camera.go_to_station(1)
				var crusher: RockCrusher3D = _bench.get_node("MineralLab/RockCrusher") as RockCrusher3D
				_vessel = _bench.get_node("Vessels/ReagentGlue") as Vessel3D
				_vessel.global_position = crusher.global_position + Vector3(0.0, crusher.hopper_height_meters + 0.12, 0.0)
				_vessel.linear_velocity = Vector3.ZERO
			if _t == 150:
				var crusher2: RockCrusher3D = _bench.get_node("MineralLab/RockCrusher") as RockCrusher3D
				var off: float = absf(_vessel.global_position.x - crusher2.global_position.x)
				_check(off > 0.06 or _vessel.global_position.y < crusher2.global_position.y + crusher2.hopper_height_meters - 0.05, "vessel pushed out of the crusher hopper (%.3f m off)" % off)
				_next()
		3:
			print("SMOKE %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
			quit(1 if _failures > 0 else 0)
	return false
