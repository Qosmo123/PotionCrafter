extends "res://tests/unit/unit_test_base.gd"
## Lab tips: every general tip comes up once before any repeats, and none is
## empty or too long for a toast.


func test_general_tips_cycle_without_repeats() -> void:
	var tips: LabTips = LabTips.new()
	tips._ready()
	var seen: Dictionary = {}
	for _i: int in LabTips.GENERAL.size():
		var text: String = tips.show_next()
		check(text != "" and text.length() < 160, "a tip fits a toast (%d chars)" % text.length())
		seen[text] = true
	check(seen.size() == LabTips.GENERAL.size(), "every tip shows once before any repeat (%d of %d)" % [seen.size(), LabTips.GENERAL.size()])
	tips.free()
