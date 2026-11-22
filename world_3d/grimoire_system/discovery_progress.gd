class_name DiscoveryProgress
extends Node
## Discovery mode: the lab starts nearly empty and grows with what the player
## finds out. A new game has a burner, a beaker and two flasks, water from the
## tap, vinegar, spirit of wine, salt of soda, honey, soap, glowberries and
## emberberries, and a few coins. Everything else on the
## shelves is unknown until it has been made or found:
##   - crush rocks in the Mineral Lab for powders (a powder counts as found),
##   - dissolve or react those powders in the starter liquids to make new
##     ingredients (malachite in vinegar gives blue vitriol, rock salt in
##     water gives brine, ...). The chemistry decides; this only notices.
## Any substance that turns up in a vessel in a useful amount is learned and
## its stock bottle appears in the satchel. Ingredients with no mineral route
## can be bought with coins from commissions. Each discovery also counts
## toward new equipment (stove, stirrer, more glassware and tools).
## Saved with the grimoire. Off for tests and demo renders (launch args).

signal learned(substance_id: StringName)

const SAVE_PATH: String = "user://grimoire.cfg"
const STARTER_SUBSTANCES: PackedStringArray = ["water", "acetic_acid", "ethanol", "baking_soda", "honey_syrup", "soap_solution", "glowberry_juice", "emberberry_juice"]
## Coins in the purse of a new lab (enough to buy two ingredients outright).
const STARTER_COINS: int = 60
## A species is noticed once a vessel holds at least this much of it.
const NOTICE_KG: float = 0.0008
const SCAN_SECONDS: float = 0.5
const BUY_PRICE_COINS: int = 30
## Equipment unlocked after this many discoveries (beyond the starters).
const EQUIPMENT_STEPS: Array = [
	[1, "HotPlate", "Stove: click its knob for gentle, even heat"],
	[2, "MagneticStirrer", "Magnetic stirrer: keeps a mixture turning by itself"],
	[3, "StirTools/WoodenSpoon", "Wooden spoon"],
	[4, "StirTools/Whisk", "Whisk: froths and aerates"],
	[5, "StirTools/SilverRod", "Silver rod: stirs with a chiral twist"],
	[7, "StirTools/ArcaneWand", "Arcane wand"],
]
## Bench vessels kept in a new lab (the rest wait in the satchel, locked).
const STARTER_VESSELS: PackedStringArray = ["Beaker", "ReagentVinegar", "FlaskSpirits", "FlaskHoney", "VialSoda", "BubbleBase", "FlaskMoonwater", "ReagentGlue"]
## Of those, the ones that start as empty glassware.
const EMPTIED_VESSELS: PackedStringArray = ["FlaskMoonwater", "ReagentGlue"]

static var instance: DiscoveryProgress = null

## True in normal play; off for tests, tools and demo renders.
var active: bool = false
## Tests switch this off so they never write the player's save.
var persist: bool = true
var known: Dictionary = {}  # substance id (String) -> true
var _scan_t: float = 0.0
var _coins_given: bool = false
var _hidden: Dictionary = {}  # node path -> original collision layer
var _hint_cache: Dictionary = {}


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	active = OS.get_cmdline_user_args().is_empty() and not OS.get_cmdline_args().has("--script")
	if not active:
		return
	_load()
	for id: String in STARTER_SUBSTANCES:
		known[id] = true
	_apply_starter_kit.call_deferred()


# --- Knowledge ----------------------------------------------------------------------

func is_known(substance_id: StringName) -> bool:
	return not active or known.has(String(substance_id))


func discovered_count() -> int:
	var n: int = 0
	for id: String in known:
		if not id in STARTER_SUBSTANCES:
			n += 1
	return n


## Learn a substance. Returns true if it was new.
func learn(substance_id: StringName, quiet: bool = false) -> bool:
	if not active or known.has(String(substance_id)):
		return false
	var idx: int = SubstanceRegistry.index_of_id(substance_id)
	if idx < 0:
		return false
	known[String(substance_id)] = true
	_save()
	learned.emit(substance_id)
	var s: SubstanceData = SubstanceRegistry.get_substance(idx)
	if not quiet and GrimoireJournal.instance != null:
		var shelf: bool = InventoryStore.instance != null and InventoryStore.instance.has_stock_for(substance_id)
		var text: String = "New ingredient discovered: %s (%s)" % [s.display_name, s.chemical_formula]
		if shelf:
			text += "! Its stock bottle is now in your satchel"
		GrimoireJournal.instance.toast.emit(text, &"discovery")
		AudioDirector.play_ui(&"discover", -5.0)
	_unlock_equipment(true)
	if InventoryStore.instance != null:
		InventoryStore.instance.changed.emit()
	return true


func buy(substance_id: StringName) -> bool:
	var journal: GrimoireJournal = GrimoireJournal.instance
	if journal == null or journal.coins < BUY_PRICE_COINS or is_known(substance_id):
		return false
	journal.coins -= BUY_PRICE_COINS
	journal.changed.emit()
	learn(substance_id)
	return true


func _process(delta: float) -> void:
	if not active:
		return
	_scan_t += delta
	if _scan_t < SCAN_SECONDS:
		return
	_scan_t = 0.0
	for v: Vessel3D in Vessel3D.all_vessels:
		var m: MixtureContainer = v.mixture
		if m == null or not v.is_inside_tree():
			continue
		for k: int in m.active_count():
			var idx: int = m.active_index(k)
			var s: SubstanceData = SubstanceRegistry.get_substance(idx)
			if known.has(String(s.substance_id)):
				continue
			if m.moles[idx] * s.molar_mass_kg_mol >= NOTICE_KG:
				learn(s.substance_id)


# --- Hints --------------------------------------------------------------------------

## How a substance can be found, worked out from the data: which powder
## turns into it (dissolving, reacting with an acid, or roasting) and which
## rock gives that powder. "" when there is no mineral route (buy it instead).
func hint_for(substance_id: StringName) -> String:
	var key: String = String(substance_id)
	if _hint_cache.has(key):
		return _hint_cache[key]
	var idx: int = SubstanceRegistry.index_of_id(substance_id)
	var hint: String = _route(SubstanceRegistry.get_substance(idx), 0) if idx >= 0 else ""
	_hint_cache[key] = hint
	return hint


func _route(target: SubstanceData, depth: int) -> String:
	if target == null:
		return ""
	var direct: String = _source_text(target)
	if direct != "":
		return direct + " in the Mineral Lab"
	var two_step: String = ""
	for i: int in SubstanceRegistry.count():
		var p: SubstanceData = SubstanceRegistry.get_substance(i)
		if p == target or not target in p.reaction_products:
			continue
		var step: String = _step_text(p)
		if step == "":
			continue
		var source: String = _source_text(p)
		if source != "":
			return "%s, then %s" % [source, step % "the powder"]
		# One step further back: the powder's own product is the thing to treat.
		if depth == 0 and two_step == "" and _route(p, 1) != "":
			two_step = "first make %s, then %s" % [p.display_name, step % "it"]
	return two_step


## What to do to `p` so it turns into its products ("%s" stands for the stuff).
func _step_text(p: SubstanceData) -> String:
	if p.dissolves_in_water:
		return "stir %s into water"
	if p.pka_acidity > 8.0:
		return "pour vinegar on %s"
	if p.decomposition_rate_per_s > 0.0 and p.decomposition_rate_per_s < 0.01:
		return "roast %s over the burner"
	return ""


## Where the powder `s` comes from: a rock from the satchel if one crushes
## to it, else a mineral found inside a rock. "" if nothing gives it.
func _source_text(s: SubstanceData) -> String:
	if s == null:
		return ""
	# Commonest first; among equals, the one richest in the powder.
	var rock: MineralData = null
	var rock_score: float = INF
	var find: MineralData = null
	var find_score: float = INF
	for m: MineralData in Rock3D.registry().values():
		var k: int = m.crush_products.find(s)
		if k < 0:
			continue
		var score: float = float(m.rarity) - (m.crush_fractions[k] if k < m.crush_fractions.size() else 0.0)
		if m.kind == MineralData.Kind.ROCK or m.kind == MineralData.Kind.SAND:
			if score < rock_score:
				rock = m
				rock_score = score
		elif score < find_score:
			find = m
			find_score = score
	if rock != null:
		return "crush %s" % rock.display_name
	if find == null:
		return ""
	var host: MineralData = null
	for m: MineralData in Rock3D.registry().values():
		if find in m.inclusions and (host == null or m.rarity < host.rarity):
			host = m
	return "crush %s (found inside %s)" % [find.display_name, host.display_name] if host != null else ""


# --- Bench -------------------------------------------------------------------------

## The bench scene (this node lives under its GrimoireJournal).
func _bench() -> Node:
	if get_parent() != null and get_parent().get_parent() != null:
		return get_parent().get_parent()
	return get_tree().current_scene


## Clear the bench down to the starter kit and hide equipment not yet earned.
func _apply_starter_kit() -> void:
	var bench: Node = _bench()
	if bench == null:
		return
	var vessels: Node = bench.get_node_or_null(^"Vessels")
	if vessels != null:
		for child: Node in vessels.get_children():
			var v: Vessel3D = child as Vessel3D
			if v == null:
				continue
			if not String(v.name) in STARTER_VESSELS:
				v.queue_free()
			elif String(v.name) in EMPTIED_VESSELS and v.mixture != null:
				v.mixture.clear()
	# Science Bench reference samples and berries you haven't met yet go too.
	var science: Node = bench.get_node_or_null(^"ScienceBench")
	if science != null:
		for child: Node in science.get_children():
			if child is Vessel3D and String(child.name).begins_with("Sample"):
				child.queue_free()
	for berry: Node in bench.find_children("*", "Berry3D", true, false):
		var juice: SubstanceData = berry.get("juice") as SubstanceData
		if juice != null and not is_known(juice.substance_id):
			berry.queue_free()
	for step: Array in EQUIPMENT_STEPS:
		_set_equipment(bench.get_node_or_null(NodePath(String(step[1]))), false)
	_unlock_equipment(false)
	if not _coins_given and persist and GrimoireJournal.instance != null:
		_coins_given = true
		GrimoireJournal.instance.coins += STARTER_COINS
		GrimoireJournal.instance.changed.emit()
		_save()
	if InventoryStore.instance != null:
		InventoryStore.instance.apply_discovery_counts()


func _unlock_equipment(announce: bool) -> void:
	var bench: Node = _bench()
	if bench == null:
		return
	var n: int = discovered_count()
	for step: Array in EQUIPMENT_STEPS:
		if n < int(step[0]):
			continue
		var node: Node = bench.get_node_or_null(NodePath(String(step[1])))
		if node == null or not _hidden.has(node.get_path()):
			continue
		_set_equipment(node, true)
		if announce and GrimoireJournal.instance != null:
			GrimoireJournal.instance.toast.emit("New equipment on the bench: %s" % step[2], &"secret")
	if InventoryStore.instance != null:
		InventoryStore.instance.apply_discovery_counts()


## Number of glassware pieces of `profile` the satchel holds at this point.
func glass_count(profile: String) -> int:
	var n: int = discovered_count()
	match profile:
		"beaker": return 1 + mini(n / 2, 3)
		"erlenmeyer": return 1 + mini(n / 3, 3)
		"round_flask": return mini(n / 3, 3)
		"apothecary_bottle": return mini(n / 2, 4)
		"vial": return 2 + mini(n, 4)
	return 0


## The next piece of equipment still to earn: {"name", "remaining"}, or {}
## once everything is on the bench.
func next_unlock() -> Dictionary:
	var n: int = discovered_count()
	for step: Array in EQUIPMENT_STEPS:
		if int(step[0]) > n:
			return {"name": String(step[2]).get_slice(":", 0), "remaining": int(step[0]) - n}
	return {}


func equipment_unlocked(node_path: String) -> bool:
	if not active:
		return true
	for step: Array in EQUIPMENT_STEPS:
		if String(step[1]) == node_path:
			return discovered_count() >= int(step[0])
	return true


func _set_equipment(node: Node, on: bool) -> void:
	if node == null:
		return
	var path: NodePath = node.get_path()
	var n3: Node3D = node as Node3D
	if not on:
		if _hidden.has(path):
			return
		var co: CollisionObject3D = node as CollisionObject3D
		_hidden[path] = co.collision_layer if co != null else 0
		if co != null:
			co.collision_layer = 0
			if co is RigidBody3D:
				(co as RigidBody3D).freeze = true
		if n3 != null:
			n3.visible = false
		node.process_mode = Node.PROCESS_MODE_DISABLED
		for child: Node in node.find_children("*", "CollisionObject3D", true, false):
			var c: CollisionObject3D = child as CollisionObject3D
			c.set_meta(&"discovery_layer", c.collision_layer)
			c.collision_layer = 0
	else:
		if not _hidden.has(path):
			return
		var co2: CollisionObject3D = node as CollisionObject3D
		if co2 != null:
			co2.collision_layer = int(_hidden[path])
			if co2 is RigidBody3D:
				(co2 as RigidBody3D).freeze = false
		_hidden.erase(path)
		if n3 != null:
			n3.visible = true
		node.process_mode = Node.PROCESS_MODE_INHERIT
		for child: Node in node.find_children("*", "CollisionObject3D", true, false):
			var c2: CollisionObject3D = child as CollisionObject3D
			if c2.has_meta(&"discovery_layer"):
				c2.collision_layer = int(c2.get_meta(&"discovery_layer"))


# --- Save ---------------------------------------------------------------------------

func _save() -> void:
	if not active or not persist:
		return
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("discovery", "known", known.keys())
	cfg.set_value("discovery", "starter_coins", _coins_given)
	if GrimoireJournal.instance != null:
		cfg.set_value("journal", "coins", GrimoireJournal.instance.coins)
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	_coins_given = bool(cfg.get_value("discovery", "starter_coins", false))
	for id: Variant in cfg.get_value("discovery", "known", []):
		known[String(id)] = true
