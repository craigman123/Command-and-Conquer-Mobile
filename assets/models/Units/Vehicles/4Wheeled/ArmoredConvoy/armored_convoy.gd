extends VehicleBase
class_name LabTruck

# ---------- LAB TRUCK SETTINGS ----------
const TRUCK_FACTION := "heroes"
const TRUCK_HEALTH := 100.0
const TRUCK_ARMOR := 0.1
const TRUCK_SPEED := 10.0
const TRUCK_ACCELERATION := 8.0
const TRUCK_BRAKE_FORCE := 18.0
const TRUCK_VISION_RANGE := 40.0
const TRUCK_MAX_CLIMB_DEGREES := 25.0

const TRUCK_FORWARD_IS_PLUS_Z := true   # flip this if the truck drives backwards

# smoke and dust come out of the back: the z sign must match the way the model faces
const TRUCK_SMOKE_OFFSET := Vector3(0.0, 0.7, -2.3)
const TRUCK_DUST_OFFSET := Vector3(0.0, 0.3, -2.5)
const TRUCK_SMOKE_AMOUNT := 30
const TRUCK_DUST_AMOUNT := 24

const IDLE_PITCH := 0.8
const MAX_PITCH := 1.3
const ENGINE_VOLUME_DB := -8.0

const MISSION_CRITICAL = true 			# if destroyed game over
const CAN_ATTACK = false
const FORCED_TARGET = false


func _init():
	forward_is_plus_z = TRUCK_FORWARD_IS_PLUS_Z

	faction = TRUCK_FACTION
	max_health = TRUCK_HEALTH
	armor = TRUCK_ARMOR
	speed = TRUCK_SPEED
	acceleration = TRUCK_ACCELERATION
	brake_force = TRUCK_BRAKE_FORCE
	vision_range = TRUCK_VISION_RANGE
	max_climb_degrees = TRUCK_MAX_CLIMB_DEGREES

	mission_critical = MISSION_CRITICAL
	can_attack = CAN_ATTACK

	smoke_offset = TRUCK_SMOKE_OFFSET
	smoke_max_amount = TRUCK_SMOKE_AMOUNT
	dust_offset = TRUCK_DUST_OFFSET
	dust_max_amount = TRUCK_DUST_AMOUNT

	idle_pitch = IDLE_PITCH
	max_pitch = MAX_PITCH
	engine_volume_db = ENGINE_VOLUME_DB
	

func _ready() -> void:
	super._ready()
	set_selected(false)     # the health bar exists by now


# the bar is always visible on the convoy, selected or not
func set_selected(value: bool):
	super.set_selected(value)
	if _hp_root:
		_hp_root.visible = not dead
		_update_health_bar()
		
func _die() -> void:
	if dead:
		return
	var pos := global_position
	super._die()
	if mission_critical:
		get_tree().call_group("game_over", "show_game_over", pos)
