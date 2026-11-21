class_name BerrySpawner
extends Node3D
## Scatters a deterministic handful of each berry kind around this node.

const BERRY_SCRIPT: Script = preload("res://world_3d/terrarium/berry_3d.gd")

@export var juices: Array[Resource] = []
@export var per_kind: int = 3
@export var scatter_radius_meters: float = 0.05
@export var seed_value: int = 11


func _ready() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var n: int = 0
	for juice_res: Resource in juices:
		for _i: int in per_kind:
			var berry: Berry3D = BERRY_SCRIPT.new() as Berry3D
			berry.juice = juice_res as SubstanceData
			berry.radius_meters = rng.randf_range(0.0075, 0.0105)
			berry.berry_mass_kg = 4.0 / 3.0 * PI * pow(berry.radius_meters, 3.0) * 1050.0
			var angle: float = rng.randf_range(0.0, TAU)
			var dist: float = sqrt(rng.randf()) * scatter_radius_meters
			berry.position = Vector3(cos(angle) * dist, 0.012 + float(n % 3) * 0.02, sin(angle) * dist)
			berry.name = "Berry_%s_%d" % [(juice_res as SubstanceData).substance_id, n]
			add_child(berry)
			n += 1
