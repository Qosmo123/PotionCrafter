class_name SubstanceRegistry
extends RefCounted
## Static index of every SubstanceData in content/substances/. Mixtures store
## one concentration slot per registered substance, so the registry must be
## fully loaded before the first MixtureContainer is created.

const SUBSTANCE_DIR: String = "res://content/substances/"

static var _substances: Array[SubstanceData] = []
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var files: PackedStringArray = DirAccess.get_files_at(SUBSTANCE_DIR)
	files.sort()
	for file_name: String in files:
		var path: String = file_name.trim_suffix(".remap")
		if not path.ends_with(".tres"):
			continue
		var substance: SubstanceData = load(SUBSTANCE_DIR + path) as SubstanceData
		if substance == null:
			push_warning("SubstanceRegistry: %s is not a SubstanceData" % path)
			continue
		if _substances.find(substance) < 0:
			_substances.append(substance)


static func count() -> int:
	ensure_loaded()
	return _substances.size()


static func get_substance(index: int) -> SubstanceData:
	ensure_loaded()
	if index < 0 or index >= _substances.size():
		return null
	return _substances[index]


static func index_of(substance: SubstanceData) -> int:
	ensure_loaded()
	return _substances.find(substance)


static func index_of_id(substance_id: StringName) -> int:
	ensure_loaded()
	for i: int in _substances.size():
		if _substances[i].substance_id == substance_id:
			return i
	return -1
