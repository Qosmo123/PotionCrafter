extends SceneTree
## Headless test runner (stand-in until gdUnit4 is installed).
## Usage: godot --headless --path . --script res://tools/run_tests.gd
## Runs every test_* method in res://tests/unit/test_*.gd; exit code 1 on failure.

const TEST_DIR: String = "res://tests/unit/"


func _initialize() -> void:
	var passed: int = 0
	var failed: int = 0
	var files: PackedStringArray = DirAccess.get_files_at(TEST_DIR)
	files.sort()
	for raw_name: String in files:
		var file_name: String = raw_name.trim_suffix(".remap")
		if not file_name.begins_with("test_") or not file_name.ends_with(".gd"):
			continue
		var script: GDScript = load(TEST_DIR + file_name) as GDScript
		if script == null:
			printerr("FAIL  %s: could not load" % file_name)
			failed += 1
			continue
		for method: Dictionary in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			var suite: Object = script.new()
			suite.call(method_name)
			var failures: PackedStringArray = suite.get("failures")
			if failures.is_empty():
				passed += 1
				print("PASS  %s::%s" % [file_name, method_name])
			else:
				failed += 1
				for f: String in failures:
					printerr("FAIL  %s::%s — %s" % [file_name, method_name, f])
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
