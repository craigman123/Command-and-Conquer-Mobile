extends VehicleBase
class_name Technical

@export_group("Turret")
@export var turret: Node3D                  # drag the turret node here (tank scene). Empty = no turret, behaves like before
@export var turret_auto_find := true        # if empty, look for a node with "turret" in its name
@export var turret_turn_speed := 150.0      # degrees per second
@export var turret_aim_tolerance := 8.0     # only fires when the gun is within this many degrees of the target
@export var turret_yaw_offset := 0.0        # gun aims sideways/backwards? try 90, -90 or 180
@export var turret_return_to_front := true  # no target: swing back to face forward

# ---------- TECHNICAL SETTINGS ----------
const TRUCK_FACTION := "villians"
const TRUCK_HEALTH := 80.0
const TRUCK_DAMAGE := 4.0
const TRUCK_RANGE := 16.0
const TRUCK_FIRE_INTERVAL := 0.05
const TRUCK_SPEED := 9.0
const BURST_DELAY = 0.5
const ARMOR = 1.0
const CAN_ATTACK = true

const TRUCK_SMOKE_OFFSET := Vector3(0.0, 0.7, 2.3)
const TRUCK_DUST_OFFSET := Vector3(0.0, 0.3, 2.5)
const TRUCK_SMOKE_AMOUNT := 40
const TRUCK_DUST_AMOUNT := 24
const TRUCK_DUST_LIFETIME := 0.5

const MUZZLE_HEIGHT := 1.4
const MUZZLE_FORWARD := 1.2

const IDLE_PITCH := 0.6
const GUN_VOLUME_DB := 3.0
const MAX_PITCH := 0.9

const FIRE_FILE := "GunSingle/gunshot_short.wav"

func _init():
	forward_is_plus_z = false   # if the truck drives backward, change to true

	faction = TRUCK_FACTION
	max_health = TRUCK_HEALTH
	attack_damage = TRUCK_DAMAGE
	attack_range = TRUCK_RANGE
	fire_interval = TRUCK_FIRE_INTERVAL
	speed = TRUCK_SPEED
	burst_delay = BURST_DELAY
	armor = ARMOR
	can_attack = CAN_ATTACK

	smoke_offset = TRUCK_SMOKE_OFFSET
	smoke_max_amount = TRUCK_SMOKE_AMOUNT
	dust_offset = TRUCK_DUST_OFFSET
	dust_max_amount = TRUCK_DUST_AMOUNT
	dust_lifetime = TRUCK_DUST_LIFETIME
	
	muzzle_height = MUZZLE_HEIGHT
	muzzle_forward = MUZZLE_FORWARD
	
	sfx_dir = "res://assets/sounds/Units/"
	fire_file = FIRE_FILE
	gun_volume_db = GUN_VOLUME_DB
	idle_pitch = IDLE_PITCH
	max_pitch = MAX_PITCH
	
var _dbg := 0.0

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_dbg -= delta
	if _dbg <= 0.0:
		_dbg = 1.0
		var t := "none"
		if is_instance_valid(combat_target):
			t = str(combat_target.name)
		var parts := []
		for u in get_tree().get_nodes_in_group("player_units"):
			parts.append("%s=%.1f" % [u.name, global_position.distance_to(u.global_position)])
