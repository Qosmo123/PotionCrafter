extends RefCounted
## Minimal assertion base used by tools/run_tests.gd until gdUnit4 is installed.
## Test files are named test_*.gd, extend this script, and expose test_* methods.

var failures: PackedStringArray = PackedStringArray()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if is_nan(actual) or absf(actual - expected) > tolerance:
		failures.append("%s (expected %s ± %s, got %s)" % [message, str(expected), str(tolerance), str(actual)])
