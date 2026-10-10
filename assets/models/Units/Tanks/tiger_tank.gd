extends VehicleBase

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
const WRECK_TIME := 30.0

const IDLE_PITCH := 6.0
const GUN_VOLUME_DB := 3.0
const MAX_PITCH := 1.0

const FIRE_FILE := "GunSingle/gun_single.ogg"

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
	wreck_time = WRECK_TIME
	
	sfx_dir = "res://assets/sounds/Units/"
	fire_file = FIRE_FILE
	gun_volume_db = GUN_VOLUME_DB
	idle_pitch = IDLE_PITCH
	max_pitch = MAX_PITCH
