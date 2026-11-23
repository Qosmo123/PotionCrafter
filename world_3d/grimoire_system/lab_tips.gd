class_name LabTips
extends Node
## Tips shown now and then as a quiet toast (bottom right). Situational tips
## come first: they read the live bench (a vessel boiling away, a still head
## dripping onto the bench, lumps that would react faster ground fine, a
## vessel close to a new recipe, coins to spend). Otherwise the next general
## tip from a shuffled list. Nothing repeats within a session. T shows the
## next tip on demand. Off for tests and demo renders.

const FIRST_TIP_S: float = 30.0
const TIP_EVERY_S: float = 75.0
## A situational tip waits for its situation to hold this long (no flicker).
const SITUATION_HOLD_S: float = 2.5

const GENERAL: PackedStringArray = [
	"Right-drag moves the view, even while you carry something.",
	"Hold Shift while moving for slow, precise placement.",
	"Wheel while holding tilts the glass by hand; wheel while pouring makes the pour faster or slower.",
	"Circle the mouse (or hold S) with a glass in your hand to swirl it.",
	"Set a filled vessel in the cork & wax dish (or press B while holding it): corked, sealed and labelled.",
	"Press E, or use the satchel tab on the right edge, to put away what you're holding.",
	"The \"???\" rows in the satchel each carry a hint about where that ingredient comes from.",
	"Click the discovery tally on the HUD for \"Things to try next\".",
	"Press G for the Grimoire: the recipes you've found, their formulas, and commissions.",
	"Pick up the magnifying glass and hold it over a vessel for a quick reading.",
	"F3 shows the lab readout: temperatures, masses and more.",
	"Chalk shapes on the bench make fields: a triangle heats, a square chills, a hexagon stirs, a circle wards.",
	"The magnetic stirrer (click it, or M) keeps a mixture turning by itself.",
	"Spirit boils near 78 °C and water at 100 °C: heat a mixture gently and the spirit leaves first.",
	"A still head fitted on a heated flask catches what boils off and drips it, cooled, from its arm.",
	"Fine powder reacts faster: grind it in the mortar until its tag reads \"Finely ground\".",
	"In the mortar, the wheel or Space pounds with the pestle. A hard blow can strike sparks.",
	"Powders heap up and slide once tipped past their angle of repose; damp powder stands steeper.",
	"In the Mineral Lab, click the rock crate (or R) to toss the next rock onto the anvil.",
	"Hit the glowing seam on a rock with the hammer to split it in one blow.",
	"The rock crusher's flywheel keeps turning for a while after you let go of the crank.",
	"Finds sell on the Trader's Scale: set the stone on the left pan, then ring the brass bell.",
	"Polished and faceted stones fetch far more than rough ones.",
	"Hover anything on the bench to see what it is and what it does.",
]

static var instance: LabTips = null

var hud: HudOverlay = null
var enabled: bool = not OS.get_cmdline_args().has("--script") and OS.get_cmdline_user_args().is_empty()
var _order: PackedInt32Array = PackedInt32Array()
var _next_general: int = 0
var _since_tip_s: float = TIP_EVERY_S - FIRST_TIP_S
var _shown: Dictionary = {}  # situational tip id -> true
var _held: Dictionary = {}  # situational tip id -> seconds its situation has held
var _scan_s: float = 0.0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	for i: int in GENERAL.size():
		_order.append(i)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for i: int in range(_order.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t: int = _order[i]
		_order[i] = _order[j]
		_order[j] = t


func _process(delta: float) -> void:
	if not enabled:
		return
	_since_tip_s += delta
	_scan_s += delta
	if _scan_s < 0.5:
		return
	var dt: float = _scan_s
	_scan_s = 0.0
	var situational: String = _situation(dt)
	if situational != "":
		_show(situational)
	elif _since_tip_s >= TIP_EVERY_S:
		show_next()


## Show the next tip now (the T key). Returns its text.
func show_next() -> String:
	var text: String = _situation(SITUATION_HOLD_S)
	if text == "":
		if _order.is_empty():
			return ""
		text = GENERAL[_order[_next_general % _order.size()]]
		_next_general += 1
	_show(text)
	return text


func _show(text: String) -> void:
	_since_tip_s = 0.0
	if hud != null:
		hud.show_toast("Tip  ·  " + text, &"tip")


## The first situational tip whose situation has held for a moment and that
## hasn't been shown yet ("" if none). `dt` is the time since the last scan.
func _situation(dt: float) -> String:
	for id: String in ["still_spill", "boiling_away", "lumps", "warm", "coins"]:
		if _shown.has(id):
			continue
		var text: String = _check(id)
		if text == "":
			_held[id] = 0.0
			continue
		_held[id] = float(_held.get(id, 0.0)) + dt
		if float(_held[id]) >= SITUATION_HOLD_S:
			_shown[id] = true
			return text
	return ""


func _check(id: String) -> String:
	match id:
		"still_spill":
			for head: StillHead3D in StillHead3D.all_heads:
				if head.flask != null and head.flow_kg_s > 1e-6 and head.receiver == null:
					return "The still head is dripping onto the bench: set an empty glass under the end of its arm."
		"boiling_away":
			var head_ready: bool = false
			for head: StillHead3D in StillHead3D.all_heads:
				if head.flask == null and head.visible and head.is_inside_tree() and head.collision_layer != 0:
					head_ready = true
			if head_ready:
				for v: Vessel3D in Vessel3D.all_vessels:
					if v.is_boiling and v.still_head == null and not (v is MortarBowl3D):
						return "Your %s is boiling away into the room. Fit the still head on it, and set an empty glass under the arm to catch what boils off." % Vessel3D.short_name(v)
		"lumps":
			for v: Vessel3D in Vessel3D.all_vessels:
				var m: MixtureContainer = v.mixture
				if m != null and not (v is MortarBowl3D) and m.grain_surface < 1.5 and m.get_solid_mass_kg() > 0.002 and m.get_liquid_volume_m3() > 5e-6:
					return "Lumps react slowly. Grind powders fine in the mortar first: fine powder reacts several times faster."
		"warm":
			for v: Vessel3D in Vessel3D.all_vessels:
				if v.discovery_warmth >= 0.78:
					return "A golden shimmer means a vessel is close to a new recipe. Hover it, or look through the lens, for a hint."
		"coins":
			var dp: DiscoveryProgress = DiscoveryProgress.instance
			if dp != null and dp.active and GrimoireJournal.instance != null and GrimoireJournal.instance.coins >= DiscoveryProgress.BUY_PRICE_COINS + 20:
				return "You have %d ◉. Locked satchel ingredients with no mineral route can be bought with coins." % GrimoireJournal.instance.coins
	return ""
