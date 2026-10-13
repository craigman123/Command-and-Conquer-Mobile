extends VehicleBase

@export_group("Bone Turret")
@export var skeleton: Skeleton3D
@export var bone_name := "Turret_07"
@export var turret_turn_speed := 1.0        # radians per second
@export var yaw_offset := 0.0               # if it aims 90/180 off, try PI/2, -PI/2 or PI
@export var rotation_axis := Vector3.UP     # the bone's local axis that swings the turret
@export var scan_range := 30.0
@export var return_to_rest := true
@export var muzzle_bone_name := "BulletSpawn_09"
@export var muzzle_offset := Vector3.ZERO   # nudge in the bone's local space if the flash is off the tip
@export var muzzle_node: Node3D

var _turret_world := 0.0
var _turret_ready := false
var _muzzle_bone := -1
var _bone := -1
var _rest: Quaternion
var _turret_angle := 0.0
var _scan_timer2 := 0.0
var _scan_target: VehicleBase = null
var _swing_axis := Vector3.UP

# ---------- TANK SETTINGS ----------
const TANK_FACTION := "heroes"
const TANK_HEALTH := 100.0
const TANK_DAMAGE := 20.0
const TANK_RANGE := 25.0
const TANK_FIRE_INTERVAL := 2.0
const TANK_SPEED := 5.0
const TANK_ARMOR := 0.8
const TANK_BURST_SIZE := 1
const CAN_ATTACK = true
const FORCED_TARGET = true

const TANK_SMOKE_OFFSET := Vector3(0.0, 0.7, 2.3)
const TANK_DUST_OFFSET := Vector3(0.0, 0.3, 2.5)
const TANK_SMOKE_AMOUNT := 40
const TANK_DUST_AMOUNT := 24
const TANK_DUST_LIFETIME := 0.5

const MUZZLE_HEIGHT := 1.4
const MUZZLE_FORWARD := 1.2

const IDLE_PITCH := 0.6
const GUN_VOLUME_DB := 17.0
const MAX_PITCH := 1.0

const FIRE_FILE := "GunSingle/tank_shot_single.ogg"

func _init():
	forward_is_plus_z = false

	faction = TANK_FACTION
	max_health = TANK_HEALTH
	attack_damage = TANK_DAMAGE
	attack_range = TANK_RANGE
	fire_interval = TANK_FIRE_INTERVAL
	speed = TANK_SPEED
	armor = TANK_ARMOR
	burst_size = TANK_BURST_SIZE
	can_attack = CAN_ATTACK

	smoke_offset = TANK_SMOKE_OFFSET
	smoke_max_amount = TANK_SMOKE_AMOUNT
	dust_offset = TANK_DUST_OFFSET
	dust_max_amount = TANK_DUST_AMOUNT
	dust_lifetime = TANK_DUST_LIFETIME

	muzzle_height = MUZZLE_HEIGHT
	muzzle_forward = MUZZLE_FORWARD

	sfx_dir = "res://assets/sounds/Units/"
	fire_file = FIRE_FILE
	gun_volume_db = GUN_VOLUME_DB
	idle_pitch = IDLE_PITCH
	max_pitch = MAX_PITCH


func _ready() -> void:
	super._ready()
	if skeleton == null:
		skeleton = find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		push_warning("Tank: no Skeleton3D found")
		return
	_muzzle_bone = skeleton.find_bone(muzzle_bone_name)
	_bone = skeleton.find_bone(bone_name)
	if _bone == -1:
		push_warning("Tank: bone not found: " + bone_name)
		return
	_rest = skeleton.get_bone_rest(_bone).basis.get_rotation_quaternion()
	var bone_world_basis := (skeleton.global_transform * skeleton.get_bone_global_rest(_bone)).basis.orthonormalized()
	_swing_axis = (bone_world_basis.inverse() * global_transform.basis.orthonormalized().y).normalized()
	print("T72 swing axis=", _swing_axis)
	print("T72 muzzle bone idx=", _muzzle_bone, " skeleton scale=", skeleton.global_transform.basis.get_scale())
	if _muzzle_bone != -1:
		print("T72 muzzle bone pose origin=", skeleton.get_bone_global_pose(_muzzle_bone).origin)
	call_deferred("_debug_muzzle")
	
func _muzzle_position() -> Vector3:
	if muzzle_node != null:
		return muzzle_node.global_position
	if skeleton != null and _muzzle_bone != -1:
		var xf := skeleton.global_transform * skeleton.get_bone_global_pose(_muzzle_bone)
		return xf * muzzle_offset
	return super._muzzle_position()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_update_turret(delta)


func _body_yaw() -> float:
	var f := global_transform.basis.orthonormalized() * Vector3(0, 0, -1)
	return atan2(-f.x, -f.z)


func _update_turret(delta: float) -> void:
	if dead or _bone == -1:
		return

	var body_yaw := _body_yaw()
	if not _turret_ready:
		_turret_world = body_yaw
		_turret_ready = true

	var t: VehicleBase = combat_target as VehicleBase
	if not is_instance_valid(t) or t.dead:
		_scan_timer2 -= delta
		if _scan_timer2 <= 0.0:
			_scan_timer2 = 0.5
			_scan_target = _find_far_enemy()
		t = _scan_target

	var desired := _turret_world
	if is_instance_valid(t) and not t.dead:
		var d := t.global_position - global_position
		d.y = 0.0
		if d.length() > 0.1:
			desired = atan2(-d.x, -d.z) + yaw_offset
	elif return_to_rest:
		desired = body_yaw

	var diff := angle_difference(_turret_world, desired)
	var step := turret_turn_speed * delta
	_turret_world += clampf(diff, -step, step)

	var relative := angle_difference(body_yaw, _turret_world)
	skeleton.set_bone_pose_rotation(_bone, _rest * Quaternion(_swing_axis, relative))

func _find_far_enemy() -> VehicleBase:
	var best: VehicleBase = null
	var best_dist := scan_range
	for u in get_tree().get_nodes_in_group("units"):
		var v := u as VehicleBase
		if v == null or v == self or v.faction == faction:
			continue
		var d := global_position.distance_to(v.global_position)
		if d < best_dist:
			best_dist = d
			best = v
	return best

func _fire_effects(muzzle: Vector3, hit_pos: Vector3):
	var dir := (hit_pos - muzzle).normalized()
	CombatVFX.tank_muzzle(self, muzzle, dir)
	CombatVFX.tracer(self, muzzle, hit_pos)

	# the blast lands when the tracer arrives (the tracer moves at 150 m/s)
	await get_tree().create_timer(muzzle.distance_to(hit_pos) / 150.0).timeout
	if not is_inside_tree():
		return
	CombatVFX.tank_impact(self, hit_pos)
	_play_impact_boom(hit_pos)

func _play_gun():
	if snd_gun == null:
		return
	snd_gun.pitch_scale = randf_range(0.65, 0.75)   # lower pitch = heavier cannon
	snd_gun.play()


func _play_impact_boom(pos: Vector3):
	if _sound_blocked():
		return
	var path := sfx_dir + explosion_file
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)
	p.unit_size = sound_unit_size * 1.5
	p.max_distance = sound_max_distance
	p.volume_db = 2.0
	p.pitch_scale = randf_range(0.9, 1.1)
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
