extends VehicleBase

@export_group("Turret")
@export var turret: Node3D                  # drag the turret node here (tank scene). Empty = no turret, behaves like before
@export var turret_auto_find := true        # if empty, look for a node with "turret" in its name
@export var turret_turn_speed := 150.0      # degrees per second
@export var turret_aim_tolerance := 8.0     # only fires when the gun is within this many degrees of the target
@export var turret_yaw_offset := 0.0        # gun aims sideways/backwards? try 90, -90 or 180
@export var turret_return_to_front := true  # no target: swing back to face forward

# ---------- TANK SETTINGS ----------
const TANK_FACTION := "heroes"        # change to "villains" if this tank is on the enemy side
const TANK_HEALTH := 300.0
const TANK_DAMAGE := 25.0
const TANK_RANGE := 25.0
const TANK_FIRE_INTERVAL := 2.0
const TANK_SPEED := 5.0

const TANK_SMOKE_OFFSET := Vector3(0.0, 0.7, 2.3)   # exhaust at the rear (+Z for this model)
const TANK_DUST_OFFSET := Vector3(0.0, 0.3, 2.5)
const TANK_SMOKE_AMOUNT := 40
const TANK_DUST_AMOUNT := 24
const TANK_DUST_LIFETIME := 0.5

const MUZZLE_HEIGHT := 1.4
const MUZZLE_FORWARD := 1.2

const IDLE_PITCH := 6.0
const GUN_VOLUME_DB := 3.0
const MAX_PITCH := 1.0

const FIRE_FILE := "GunSingle/gunshot_short.wav"

func _init():
	forward_is_plus_z = false                  # the tank model faces -Z

	faction = TANK_FACTION
	max_health = TANK_HEALTH
	attack_damage = TANK_DAMAGE
	attack_range = TANK_RANGE
	fire_interval = TANK_FIRE_INTERVAL
	speed = TANK_SPEED

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
