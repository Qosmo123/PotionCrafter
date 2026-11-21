class_name PropMaterials
extends RefCounted
## Fix-ups for materials imported from Blender glTF. Godot's importer has no
## transmission, so Blender "Glass"/"FrostGlass"/"ArcaneOrb" would render
## opaque white. Swap them for the project's tiered glass shaders.

const GLASS_PC_MATERIAL: Material = preload("res://content/materials_3d/glass_pc.tres")
const GLASS_MOBILE_MATERIAL: Material = preload("res://content/materials_3d/glass_mobile.tres")


static func apply(root: Node) -> void:
	var glass: Material = QualityTier.pick_material(GLASS_PC_MATERIAL, GLASS_MOBILE_MATERIAL)
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null:
			continue
		for surface: int in mi.mesh.get_surface_count():
			var material: Material = mi.get_active_material(surface)
			if material == null:
				continue
			var mat_name: String = material.resource_name
			if mat_name == "Glass":
				mi.set_surface_override_material(surface, glass)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			elif mat_name == "FrostGlass" or mat_name == "ArcaneOrb":
				var frosted: StandardMaterial3D = StandardMaterial3D.new()
				var src: StandardMaterial3D = material as StandardMaterial3D
				frosted.albedo_color = Color(0.7, 0.85, 1.0, 0.35)
				frosted.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				frosted.roughness = 0.3 if mat_name == "FrostGlass" else 0.05
				frosted.emission_enabled = true
				frosted.emission = src.emission if src != null else Color(0.3, 0.6, 1.0)
				frosted.emission_energy_multiplier = 0.12 if mat_name == "FrostGlass" else 2.0
				frosted.rim_enabled = true
				mi.set_surface_override_material(surface, frosted)
			elif mat_name == "FrostGlow":
				var glow: StandardMaterial3D = (material as StandardMaterial3D).duplicate() as StandardMaterial3D
				if glow != null:
					glow.emission_energy_multiplier = 0.35
					mi.set_surface_override_material(surface, glow)
