extends VehicleBase

@export_group("Turret")
@export var turret: Node3D                  # drag the turret node here (tank scene). Empty = no turret, behaves like before
@export var turret_auto_find := true        # if empty, look for a node with "turret" in its name
@export var turret_turn_speed := 150.0      # degrees per second
@export var turret_aim_tolerance := 8.0     # only fires when the gun is within this many degrees of the target
@export var turret_yaw_offset := 0.0        # gun aims sideways/backwards? try 90, -90 or 180
@export var turret_return_to_front := true  # no target: swing back to face forward

# ---------- HUMVEE SETTINGS (edit these) ----------
const HUMVEE_FACTION := "heroes"
const HUMVEE_HEALTH := 120.0
const HUMVEE_DAMAGE := 2.0
const HUMVEE_RANGE := 18.0
const HUMVEE_FIRE_INTERVAL := 0.1
const HUMVEE_SPEED := 10.0

# smoke and dust spawn points: (left/right, up/down, front/back)
const HUMVEE_SMOKE_OFFSET := Vector3(0.0, 0.7, -1.3)
const HUMVEE_DUST_OFFSET := Vector3(0.0, 0.3, -2.0)
const HUMVEE_SMOKE_AMOUNT := 40
const HUMVEE_DUST_AMOUNT := 24
const HUMVEE_DUST_LIFETIME := 0.5

const MUZZLE_HEIGHT := 1.4
const MUZZLE_FORWARD := 1.2

const IDLE_PITCH := 0.6
const GUN_VOLUME_DB := 3.0
const MAX_PITCH := 0.9
var BURST_SIZE = 1
var FIRE_INTERVAL = 1.0

const FIRE_FILE := "GunSingle/gunshot_short.wav"

func _init():
	dust_enabled = true

	faction = HUMVEE_FACTION
	max_health = HUMVEE_HEALTH
	attack_damage = HUMVEE_DAMAGE
	attack_range = HUMVEE_RANGE
	fire_interval = HUMVEE_FIRE_INTERVAL
	speed = HUMVEE_SPEED
	burst_size = BURST_SIZE
	fire_interval = FIRE_INTERVAL

	smoke_offset = HUMVEE_SMOKE_OFFSET
	smoke_max_amount = HUMVEE_SMOKE_AMOUNT
	dust_offset = HUMVEE_DUST_OFFSET
	dust_max_amount = HUMVEE_DUST_AMOUNT
	dust_lifetime = HUMVEE_DUST_LIFETIME
	
	muzzle_height = MUZZLE_HEIGHT
	muzzle_forward = MUZZLE_FORWARD
	
	sfx_dir = "res://assets/sounds/Units/"
	fire_file = FIRE_FILE
	gun_volume_db = GUN_VOLUME_DB
	idle_pitch = IDLE_PITCH
	max_pitch = MAX_PITCH


func _find_model() -> Node3D:
	return $humvee
