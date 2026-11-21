class_name ContactShadow3D
extends Decal
## Soft contact shadow (ambient-occlusion blob) under a body, projected onto
## whatever is just beneath it. Real shadow maps are too coarse to darken the
## few millimetres where glass meets wood; this grounds every vessel and rock.
## Follows its body without rotating with it (top-level), and fades out as the
## body is lifted, because the decal's projection box only reaches a few cm.

const PROJECTION_DEPTH_METERS: float = 0.12

static var _tex: ImageTexture = null

var _body: Node3D = null
## Height of the body's underside relative to its origin (usually <= 0).
var _base_offset: float = 0.0


## Attach a contact shadow of the given footprint radius to `body`.
## `base_offset_meters`: where its underside is, relative to its origin.
static func attach(body: Node3D, radius_meters: float, base_offset_meters: float = 0.0) -> ContactShadow3D:
	var d: ContactShadow3D = ContactShadow3D.new()
	d._body = body
	d._base_offset = base_offset_meters
	d.size = Vector3(radius_meters * 3.2, PROJECTION_DEPTH_METERS, radius_meters * 3.2)
	body.add_child(d)
	return d


func _ready() -> void:
	top_level = true
	texture_albedo = _blob()
	modulate = Color(0.0, 0.0, 0.0, 0.62)
	albedo_mix = 1.0
	upper_fade = 0.15
	lower_fade = 0.6
	cull_mask = 1
	# Ignore surfaces of other bodies above the bench (no shadows on glass).
	distance_fade_enabled = true
	distance_fade_begin = 8.0
	distance_fade_length = 2.0


func _process(_delta: float) -> void:
	if _body == null or not is_instance_valid(_body):
		queue_free()
		return
	# Centre the projection box just below the body's centre so it reaches the
	# surface it rests on; lifted bodies leave it behind and the shadow fades.
	global_transform = Transform3D(Basis.IDENTITY, _body.global_position + Vector3(0.0, _base_offset - PROJECTION_DEPTH_METERS * 0.3, 0.0))


static func _blob() -> ImageTexture:
	if _tex != null:
		return _tex
	var n: int = 64
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y: int in n:
		for x: int in n:
			var d: float = Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
	_tex = ImageTexture.create_from_image(img)
	return _tex
