extends VehicleBase
class_name Technical

# ---------- TECHNICAL SETTINGS ----------
const TRUCK_FACTION := "villains"
const TRUCK_HEALTH := 80.0
const TRUCK_DAMAGE := 1.0
const TRUCK_RANGE := 16.0
const TRUCK_FIRE_INTERVAL := 0.05
const TRUCK_SPEED := 9.0

const TRUCK_SMOKE_OFFSET := Vector3(0.0, 0.7, 2.3)
const TRUCK_DUST_OFFSET := Vector3(0.0, 0.3, 2.5)
const TRUCK_SMOKE_AMOUNT := 40
const TRUCK_DUST_AMOUNT := 24
const TRUCK_DUST_LIFETIME := 0.5

const MUZZLE_HEIGHT := 1.4
const MUZZLE_FORWARD := 1.2
const WRECK_TIME := 30.0

const IDLE_PITCH := 6.0
const GUN_VOLUME_DB := 3.0
const MAX_PITCH := 1.0

const FIRE_FILE := "GunSingle/gun_single.ogg"

func _init():
	forward_is_plus_z = false   # if the truck drives backward, change to true

	faction = TRUCK_FACTION
	max_health = TRUCK_HEALTH
	attack_damage = TRUCK_DAMAGE
	attack_range = TRUCK_RANGE
	fire_interval = TRUCK_FIRE_INTERVAL
	speed = TRUCK_SPEED

	smoke_offset = TRUCK_SMOKE_OFFSET
	smoke_max_amount = TRUCK_SMOKE_AMOUNT
	dust_offset = TRUCK_DUST_OFFSET
	dust_max_amount = TRUCK_DUST_AMOUNT
	dust_lifetime = TRUCK_DUST_LIFETIME
	
	muzzle_height = MUZZLE_HEIGHT
	muzzle_forward = MUZZLE_FORWARD
	wreck_time = WRECK_TIME
	
	sfx_dir = "res://assets/sounds/Units/"
	fire_file = FIRE_FILE
	gun_volume_db = GUN_VOLUME_DB
	idle_pitch = IDLE_PITCH
	max_pitch = MAX_PITCH
