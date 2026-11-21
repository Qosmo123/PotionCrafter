class_name PropDressing
extends Node3D
## Shared toolkit for fine set-dressing detail added in code on top of the
## Blender props: boxes, domed heads (rivets, nails, bolts), rods, flat paint
## and lettering. Call the `_box` / `_dome` / `_cyl` / `_tint` helpers with
## world-space positions, then `_build_batches()` once: every shape of one
## material becomes a single MultiMesh, so a whole station's detail costs a
## handful of draw calls. Lettering is Label3D (one draw each).

var _boxes: Dictionary = {}  # material key -> Array[Transform3D]
var _domes: Dictionary = {}  # material key -> Array[Transform3D]
var _cyls: Dictionary = {}  # material key -> Array[Transform3D]
var _tints: Array[Transform3D] = []  # flat-coloured boxes (chart swatches, ink)
var _tint_colors: PackedColorArray = PackedColorArray()


## A flat-coloured box with its own orientation (dial ticks, clock hands).
func _tint_xf(xf: Transform3D, color: Color) -> void:
	_tints.append(xf)
	_tint_colors.append((color * 0.72).srgb_to_linear())


## A rod between two points (peg, shaft, handle).
func _cyl(material: StringName, from: Vector3, to: Vector3, radius: float) -> void:
	if not _cyls.has(material):
		_cyls[material] = []
	var axis: Vector3 = to - from
	var length: float = axis.length()
	var y: Vector3 = axis / maxf(length, 1e-6)
	var x: Vector3 = y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.UP).normalized()
	var basis: Basis = Basis(x * radius, y * length, x.cross(y) * radius)
	(_cyls[material] as Array).append(Transform3D(basis, (from + to) * 0.5))


## A flat-coloured box (ink, paint, swatches).
func _tint(center: Vector3, size: Vector3, color: Color) -> void:
	_tints.append(Transform3D(Basis.from_scale(size), center))
	# MultiMesh instance colours are read as linear light.
	_tint_colors.append((color * 0.72).srgb_to_linear())


func _box(material: StringName, center: Vector3, size: Vector3) -> void:
	if not _boxes.has(material):
		_boxes[material] = []
	(_boxes[material] as Array).append(Transform3D(Basis.from_scale(size), center))


## A domed head (rivet, nail, bolt) sitting on a surface with this normal.
func _dome(material: StringName, at: Vector3, normal: Vector3, radius: float) -> void:
	if not _domes.has(material):
		_domes[material] = []
	var y: Vector3 = normal.normalized()
	var x: Vector3 = y.cross(Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.UP).normalized()
	var basis: Basis = Basis(x, y, x.cross(y)).scaled(Vector3.ONE * radius)
	(_domes[material] as Array).append(Transform3D(basis, at))


func _material(key: StringName) -> Material:
	var m: StandardMaterial3D
	match key:
		&"iron":
			m = PropMaterials.textured("iron", Color(0.5, 0.5, 0.53), 0.12, 0.6).duplicate() as StandardMaterial3D
		&"brass":
			m = PropMaterials.textured("metal", Color(0.95, 0.72, 0.34), 0.12, 0.85).duplicate() as StandardMaterial3D
		&"wood":
			m = PropMaterials.textured("wood", Color(0.5, 0.33, 0.19), 0.2).duplicate() as StandardMaterial3D
		&"leather":
			m = PropMaterials.textured("leather", Color(0.2, 0.3, 0.2), 0.1).duplicate() as StandardMaterial3D
		&"bristle":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.82, 0.74, 0.56)
			m.roughness = 0.95
			return m
		&"slate":
			m = PropMaterials.textured("stone", Color(0.13, 0.15, 0.15), 0.3).duplicate() as StandardMaterial3D
		&"red":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.75, 0.08, 0.06)
			m.roughness = 0.3
			return m
		&"pencil":
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.8, 0.62, 0.12)
			m.roughness = 0.5
			return m
		_:
			m = StandardMaterial3D.new()
			m.albedo_color = Color(0.035, 0.03, 0.028)
			m.roughness = 0.9
			return m
	# The instances are scaled, so map the texture in world space.
	m.uv1_world_triplanar = true
	return m


func _build_batches() -> void:
	var cube: BoxMesh = BoxMesh.new()
	cube.size = Vector3.ONE
	var dome: SphereMesh = SphereMesh.new()
	dome.radius = 1.0
	dome.height = 1.0
	dome.is_hemisphere = true
	dome.radial_segments = 10
	dome.rings = 3
	var rod: CylinderMesh = CylinderMesh.new()
	rod.top_radius = 1.0
	rod.bottom_radius = 1.0
	rod.height = 1.0
	rod.radial_segments = 24
	rod.rings = 1
	if not _tints.is_empty():
		var tm: MultiMesh = MultiMesh.new()
		tm.transform_format = MultiMesh.TRANSFORM_3D
		tm.use_colors = true
		tm.mesh = cube
		tm.instance_count = _tints.size()
		var inv: Transform3D = global_transform.affine_inverse()
		for i: int in _tints.size():
			tm.set_instance_transform(i, inv * _tints[i])
			tm.set_instance_color(i, _tint_colors[i])
		var paint: StandardMaterial3D = StandardMaterial3D.new()
		paint.vertex_color_use_as_albedo = true
		paint.roughness = 0.85
		# Ink and paint keep their colour in the bright window light.
		paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var tmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		tmi.name = "Paint"
		tmi.multimesh = tm
		tmi.material_override = paint
		tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tmi)
	for pair: Array in [[_boxes, cube, "Boxes"], [_domes, dome, "Heads"], [_cyls, rod, "Rods"]]:
		var groups: Dictionary = pair[0]
		for key: StringName in groups:
			var list: Array = groups[key]
			var mm: MultiMesh = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = pair[1]
			mm.instance_count = list.size()
			var to_local: Transform3D = global_transform.affine_inverse()
			for i: int in list.size():
				mm.set_instance_transform(i, to_local * (list[i] as Transform3D))
			var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
			mmi.name = "%s_%s" % [pair[2], key]
			mmi.multimesh = mm
			mmi.material_override = _material(key)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)


## Painted or engraved lettering, scaled to fit `width_m` and capped at `height_m`.
func _text(text: String, at: Vector3, width_m: float, height_m: float, color: Color, text_font: Font = null) -> void:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font = text_font if text_font != null else CosmicTheme.display_font()
	label.font_size = 64
	label.outline_size = 0
	label.modulate = color
	label.shaded = true
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var size_px: Vector2 = label.font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 64)
	label.pixel_size = minf(width_m / maxf(size_px.x, 1.0), height_m / maxf(size_px.y * 0.72, 1.0))
	add_child(label)
	label.global_position = at
