class_name Flat2D
extends RefCounted
## Keeps loose objects playing in the 2D side view: they slide left/right,
## rise and fall, and tip over sideways (rotation about the view axis), but
## never roll toward or away from the camera or spin on the spot.
##
## Only rotation is locked. Locking depth too would pin objects (Jolt snaps a
## depth-locked body back to its old depth when code moves it), and with no
## rolling there is nothing to carry them off in depth anyway.

const META: StringName = &"flat_2d"


static func lock(body: RigidBody3D) -> void:
	body.set_meta(META, true)
	body.axis_lock_angular_x = true
	body.axis_lock_angular_y = true


## Kept for the grabber's hold/release hooks (depth stays free).
static func free_depth(_body: RigidBody3D) -> void:
	pass


## On release, drop any sideways (depth) drift so it settles where it is.
static func relock_depth(body: RigidBody3D) -> void:
	if body != null and is_instance_valid(body) and body.has_meta(META):
		var v: Vector3 = body.linear_velocity
		body.linear_velocity = Vector3(v.x, v.y, 0.0)
