extends Node3D
## Visual-only prop group (no collision): applies the glass material fix-ups.

func _ready() -> void:
	PropMaterials.apply(self)
