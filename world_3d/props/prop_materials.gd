class_name PropMaterials
extends RefCounted
## Fix-ups for materials imported from Blender glTF. Godot's importer has no
## transmission, so Blender "Glass"/"FrostGlass"/"ArcaneOrb" would render
## opaque white. Swap them for the project's tiered glass shaders.
##
## 4K surface detail: every other Blender material is mapped to a tileable 4K
## PBR set (content/textures_4k, made by tools/gen_textures_4k.py): albedo
## detail tinted by the material's own colour, a normal map and a roughness
## map, applied with object-space triplanar mapping (no UV seams, and the
## texture stays put on moving props). Materials are built once and shared.

const TEX_DIR: String = "res://content/textures_4k/"
## Blender material name -> [texture set, tile size in metres].
const SURFACE_SETS: Dictionary = {
	"Oak": ["wood", 0.5], "DarkWood": ["wood", 0.5], "LightWood": ["wood", 0.45], "WandWood": ["wood", 0.2],
	"Brass": ["metal", 0.3], "Copper": ["metal", 0.3], "Silver": ["metal", 0.3], "Gilt": ["metal", 0.25],
	"Iron": ["iron", 0.3],
	"BookLeather": ["leather", 0.12], "LeatherBlue": ["leather", 0.12], "LeatherGreen": ["leather", 0.12],
	"LeatherRed": ["leather", 0.12], "Rubber": ["leather", 0.08],
	"Ceramic": ["ceramic", 0.25], "Enamel": ["ceramic", 0.25], "GlazeCream": ["ceramic", 0.25], "GlazeTeal": ["ceramic", 0.25],
	"Stone": ["stone", 0.3],
	"Parchment": ["parchment", 0.2], "PageEdge": ["parchment", 0.1],
	"Cork": ["cork", 0.06],
}

static var _textured_cache: Dictionary = {}

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
			elif SURFACE_SETS.has(mat_name) and material is StandardMaterial3D:
				mi.set_surface_override_material(surface, textured_from(material as StandardMaterial3D, mat_name))
			elif mat_name == "FrostGlow":
				var glow: StandardMaterial3D = (material as StandardMaterial3D).duplicate() as StandardMaterial3D
				if glow != null:
					glow.emission_energy_multiplier = 0.35
					mi.set_surface_override_material(surface, glow)


## Shared 4K-textured copy of a Blender material (keeps its colour as a tint,
## its metallic value and emission).
static func textured_from(src: StandardMaterial3D, mat_name: String) -> StandardMaterial3D:
	var key: String = "%s|%s" % [mat_name, src.albedo_color.to_html()]
	if _textured_cache.has(key):
		return _textured_cache[key]
	var info: Array = SURFACE_SETS[mat_name]
	var m: StandardMaterial3D = src.duplicate() as StandardMaterial3D
	apply_set(m, String(info[0]), float(info[1]))
	_textured_cache[key] = m
	return m


## Fresh 4K-textured material for props built in code (hammer, handles...).
static func textured(set_name: String, tint: Color, tile_meters: float, metallic: float = 0.0) -> StandardMaterial3D:
	var key: String = "code|%s|%s|%.3f|%.2f" % [set_name, tint.to_html(), tile_meters, metallic]
	if _textured_cache.has(key):
		return _textured_cache[key]
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = tint
	m.metallic = metallic
	apply_set(m, set_name, tile_meters)
	_textured_cache[key] = m
	return m


static func apply_set(m: StandardMaterial3D, set_name: String, tile_meters: float) -> void:
	m.albedo_texture = load(TEX_DIR + set_name + "_albedo.jpg") as Texture2D
	m.normal_enabled = true
	m.normal_texture = load(TEX_DIR + set_name + "_normal.jpg") as Texture2D
	m.normal_scale = 1.0
	m.roughness_texture = load(TEX_DIR + set_name + "_rough.jpg") as Texture2D
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	m.roughness = 1.0  # the map holds absolute roughness
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_triplanar_sharpness = 4.0
	var k: float = 1.0 / maxf(tile_meters, 0.01)
	m.uv1_scale = Vector3(k, k, k)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
