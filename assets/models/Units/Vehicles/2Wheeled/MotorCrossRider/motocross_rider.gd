extends VehicleBase
class_name MotocrossRider

@export_group("Rider Arm")
@export var shoulder: Node3D                       # drag Shoulder_R here (arm + gun)
@export var shoulder_pivot: Node3D                 # Marker3D placed at the shoulder joint
@export var vision_half_angle := 30.0              # the "pan" view cone (degrees each side)
@export var aim_rotation_degrees := Vector3(-60, 0, 0)
@export var aim_time := 0.2
@export var turn_speed_degrees := 120.0            # how fast the bike turns toward an enemy outside the cone

@export_group("Slopes")
@export var climb_slope_degrees := 65.0

# ---------- TECHNICAL SETTINGS (same as the truck) ----------
# ---------- BIKE SETTINGS ----------
const FACTION := "villians"
const HEALTH := 80.0
const DAMAGE := 2.0
const RANGE := 16.0
const FIRE_INTERVAL := 0.05
const SPEED := 9.0
const BURST_DELAY := 0.5
const ARMOR := 1.0
const CAN_ATTACK := true

const SMOKE_OFFSET := Vector3(0.0, 0.7, 2.3)
const DUST_OFFSET := Vector3(0.0, 0.3, 2.5)
const SMOKE_AMOUNT := 40
const DUST_AMOUNT := 24
const DUST_LIFETIME := 0.5

const MUZZLE_HEIGHT := 1.4
const MUZZLE_FORWARD := 1.2

const IDLE_PITCH := 0.6
const MAX_PITCH := 0.9
const GUN_VOLUME_DB := 3.0

const FIRE_FILE := "GunSingle/gunshot_short.wav"

var _rest_transform := Transform3D.IDENTITY
var _pivot := Vector3.ZERO   # shoulder joint, in the shoulder's parent space
var _aim_amount := 0.0   # 0 = riding pose, 1 = aiming
var _arm_yaw := 0.0

@export_group("Death")
@export var rider_parts: Array[Node3D] = []   # rider body node + Shoulder_R
@export var lay_down_time := 0.6
@export var lay_down_degrees := 90.0
@export var lay_down_raise := 0.3             # lifts the bike so its side doesn't sink into the ground
@export var rider_body: Node3D   # the rider node (the 3c853c...fbx one)


func _init():
	forward_is_plus_z = true   # if the bike drives backward, change to false

	faction = FACTION
	max_health = HEALTH
	attack_damage = DAMAGE
	attack_range = RANGE
	fire_interval = FIRE_INTERVAL
	speed = SPEED
	burst_delay = BURST_DELAY
	armor = ARMOR
	can_attack = CAN_ATTACK

	smoke_offset = SMOKE_OFFSET
	smoke_max_amount = SMOKE_AMOUNT
	dust_offset = DUST_OFFSET
	dust_max_amount = DUST_AMOUNT
	dust_lifetime = DUST_LIFETIME

	muzzle_height = MUZZLE_HEIGHT
	muzzle_forward = MUZZLE_FORWARD

	sfx_dir = "res://assets/sounds/Units/"
	engine_start_file = "EngineStarting/bike_start.ogg"
	engine_idle_file = "EngineIdle/bike_idle.ogg"
	engine_off_file = "EngineOff/bike_off.ogg"
	idle_pitch = 0.6 
	max_pitch = 1.4  


func _ready():
	super._ready()
	floor_max_angle = deg_to_rad(climb_slope_degrees)

	if shoulder:
		_rest_transform = shoulder.transform
		var parent := shoulder.get_parent() as Node3D
		if shoulder_pivot and parent:
			_pivot = parent.to_local(shoulder_pivot.global_position)
		else:
			_pivot = _rest_transform.origin
			push_warning(name + ": shoulder_pivot is not assigned, rotating around the node origin")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_arm(delta)
	if Engine.get_physics_frames() % 30 == 0:
		var nav := get_node_or_null("NavigationAgent3D") as NavigationAgent3D
		
func _update_arm(delta: float) -> void:
	if shoulder == null:
		return

	var has_enemy: bool = is_instance_valid(combat_target) and not combat_target.dead
	var target_yaw := 0.0
	var in_view := false

	if has_enemy:
		var p := to_local(combat_target.global_position)
		var yaw := atan2(p.x, p.z) if forward_is_plus_z else atan2(-p.x, -p.z)
		in_view = absf(yaw) <= deg_to_rad(vision_half_angle)
		if in_view:
			target_yaw = yaw
		else:
			# enemy outside the view cone: turn the whole bike toward it (it keeps moving)
			var step := deg_to_rad(turn_speed_degrees) * delta
			rotate_y(clampf(yaw, -step, step))

	# arm only raises while the enemy is inside the view cone, otherwise it relaxes
	_aim_amount = move_toward(_aim_amount, 1.0 if in_view else 0.0, delta / aim_time)
	_arm_yaw = lerp_angle(_arm_yaw, target_yaw, 10.0 * delta)

	var raise_q := Quaternion.from_euler(Vector3(
		deg_to_rad(aim_rotation_degrees.x),
		deg_to_rad(aim_rotation_degrees.y) + _arm_yaw,
		deg_to_rad(aim_rotation_degrees.z)))
	var aim_q := Quaternion.IDENTITY.slerp(raise_q, _aim_amount)

	# rotate ONLY the arm node, around the shoulder joint. The rider body is never touched.
	var rot := Transform3D(Basis(aim_q), Vector3.ZERO)
	var to_pivot := Transform3D(Basis.IDENTITY, _pivot)
	var from_pivot := Transform3D(Basis.IDENTITY, -_pivot)
	shoulder.transform = to_pivot * rot * from_pivot * _rest_transform
	
func _die() -> void:
	if dead:
		return
	_hide_rider()
	_lay_down_bike()
	super._die()


func _hide_rider() -> void:
	if shoulder:
		shoulder.visible = false          # arm + gun
	if rider_body:
		rider_body.visible = false        # torso, head, legs
	else:
		push_warning(name + ": rider_body is not assigned, so the rider stays visible")
	for part in rider_parts:
		if is_instance_valid(part):
			part.visible = false


func _lay_down_bike() -> void:
	if model == null:
		return
	var side := 1.0 if randf() < 0.5 else -1.0   # falls left or right
	var start_basis := model.basis
	var start_pos := model.position

	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float):
		model.basis = Basis(Vector3.BACK, a * side) * start_basis,
		0.0, deg_to_rad(lay_down_degrees), lay_down_time)
	tw.tween_property(model, "position", start_pos + Vector3(0.0, lay_down_raise, 0.0), lay_down_time)
