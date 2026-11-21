@tool
class_name VesselProfile
extends Resource
## Revolved glassware shape exported by tools/blender/build_glassware.py.
## `inner_profile` holds (radius, height) points of the cavity wall, from the
## bottom centre up to the opening, in the vessel's local frame (origin at mid-height).

@export var vessel_name: String = ""
@export var glass_mesh: Mesh
@export var liquid_mesh: Mesh
@export var inner_profile: PackedVector2Array = PackedVector2Array()
@export var outer_radius_meters: float = 0.03
@export var height_meters: float = 0.14
@export var glass_mass_kg: float = 0.1
@export var modelled_capacity_m3: float = 0.0
