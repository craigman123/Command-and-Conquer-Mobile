extends Node
class_name LastSeenMarkers

# 1. Hides enemies that your units can't currently see (uses the FogOfWar node's vision).
# 2. Shows ONE "!" marker per group of enemies that were last seen close together.
# Put this script on a plain Node in the map scene (your "LastSeen" node).

# ---------- SETTINGS (edit these, or change them in the Inspector) ----------
@export var ally_faction := "heroes"
@export var enemy_faction := "villains"
@export var any_other_faction_is_enemy := true    # every faction that isn't ally_faction counts as an enemy
@export var fog_path: NodePath = ^"../FogOfWar"   # the fog node: its vision decides what is "seen"
@export var hide_unseen_enemies := true           # enemies are invisible unless your units can see them
@export var check_interval := 0.15                # seconds between scans
@export var unit_refresh_interval := 1.0          # how often to look for new/removed units

@export var marker_text := "!"
@export var group_radius := 30.0                  # enemies last seen within this distance share ONE marker
@export var marker_lifetime := 20.0               # seconds before a marker disappears
@export var clear_radius := 8.0                   # an ally this close to a spot (not seeing the enemy) clears it
@export var marker_height := 2.5
@export var marker_color := Color(0.546, 0.0, 0.007, 1.0)

@export_group("Only used if no fog node is found")
@export var vision_range := 35.0
@export var require_line_of_sight := true

@export var debug_print := false                  # prints what it found every 2 s (turn on if something is wrong)
# -----------------------------------------------------------------------------

var _fog: Node = null
var _allies: Array = []
var _enemies: Array = []
var _last_refresh := -100.0
var _last_debug := -10.0
var _faction_counts := {}   # faction name -> how many units, for the debug print
var _memory := {}           # enemy instance id -> { pos, seen, lost_at }
var _markers: Array = []    # pool of Label3D, one per group
var _timer := 0.0
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_fog = get_node_or_null(fog_path)
	if _fog == null and get_tree().current_scene != null:
		_fog = get_tree().current_scene.find_child("FogOfWar", true, false)
	if _fog != null and not _fog.has_method("is_visible_at"):
		_fog = null
	if _fog == null:
		push_warning("LastSeen: no FogOfWar node with is_visible_at() found, using its own vision check")


func _process(delta: float) -> void:
	_timer += delta
	if _timer < check_interval:
		return
	_timer = 0.0
	_scan()


func _scan() -> void:
	var now := Time.get_ticks_msec() / 1000.0

	if now - _last_refresh > unit_refresh_interval:
		_last_refresh = now
		_refresh_units()

	var allies := _alive(_allies)
	var enemies := _alive(_enemies)

	# 1. which enemies can we see right now?
	var seen_now := {}
	for e in enemies:
		if _is_spotted(e, allies):
			seen_now[e.get_instance_id()] = e

	# 2. hide every enemy we can't see
	if hide_unseen_enemies:
		for e in enemies:
			e.visible = seen_now.has(e.get_instance_id())

	if debug_print and now - _last_debug > 2.0:
		_last_debug = now
		print("LastSeen: allies=%d enemies=%d seen=%d remembered=%d fog=%s factions=%s" % [
			allies.size(), enemies.size(), seen_now.size(), _memory.size(), _fog != null, _faction_counts])

	# 3. enemies in view: remember where they are
	for id in seen_now:
		var e: Node3D = seen_now[id]
		var entry: Dictionary = _memory.get(id, {})
		if entry.is_empty():
			entry = {"pos": e.global_position, "seen": true, "lost_at": 0.0}
			_memory[id] = entry
		entry["pos"] = e.global_position
		entry["seen"] = true

	# 4. enemies we remembered but can't see now
	var lost: Array = []
	for id in _memory.keys():
		var entry: Dictionary = _memory[id]
		var enemy := instance_from_id(id)

		# destroyed or removed: forget it
		if enemy == null or not is_instance_valid(enemy) or _is_dead(enemy):
			_memory.erase(id)
			continue

		if seen_now.has(id):
			continue

		if entry["seen"]:                       # just lost sight of it
			entry["seen"] = false
			entry["lost_at"] = now

		# too old, or one of our units went to check the spot and found nothing
		var age: float = now - entry["lost_at"]
		if age > marker_lifetime or _ally_checked_spot(allies, entry["pos"]):
			_memory.erase(id)
			continue

		lost.append(entry)

	_update_markers(lost, now)


# Groups lost enemies that are close together and shows ONE marker per group.
func _update_markers(lost: Array, now: float) -> void:
	var groups: Array = []   # each: { sum: Vector3, count: int, newest: float }
	for entry in lost:
		var pos: Vector3 = entry["pos"]
		var placed := false
		for g in groups:
			var center: Vector3 = g["sum"] / float(g["count"])
			if _flat_dist(center, pos) <= group_radius:
				g["sum"] += pos
				g["count"] += 1
				g["newest"] = maxf(g["newest"], entry["lost_at"])
				placed = true
				break
		if not placed:
			groups.append({"sum": pos, "count": 1, "newest": entry["lost_at"]})

	while _markers.size() < groups.size():
		_markers.append(_make_marker())

	for i in _markers.size():
		var m: Label3D = _markers[i]
		if i >= groups.size():
			m.visible = false
			continue
		var g: Dictionary = groups[i]
		m.visible = true
		m.global_position = g["sum"] / float(g["count"]) + Vector3.UP * marker_height
		var fade := clampf((now - g["newest"]) / marker_lifetime, 0.0, 1.0)
		m.modulate.a = lerpf(1.0, 0.3, fade)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# Finds units by their faction, so it doesn't depend on which groups they are in.
func _refresh_units() -> void:
	_allies.clear()
	_enemies.clear()
	_faction_counts.clear()
	# search the whole tree, not just the current scene, in case the map is loaded under another node
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var f = n.get("faction")
		if f == null:
			continue
		var fname := str(f)
		_faction_counts[fname] = int(_faction_counts.get(fname, 0)) + 1
		if fname == ally_faction:
			_allies.append(n)
		elif fname == enemy_faction or (any_other_faction_is_enemy and fname != ""):
			_enemies.append(n)


func _alive(list: Array) -> Array:
	var out: Array = []
	for u in list:
		if is_instance_valid(u) and not _is_dead(u):
			out.append(u)
	return out


# Seen = the fog says that spot is visible (same vision as the dark overlay).
func _is_spotted(e: Node3D, allies: Array) -> bool:
	if _fog != null:
		return _fog.is_visible_at(e.global_position)
	var r2 := vision_range * vision_range
	for a in allies:
		if a.global_position.distance_squared_to(e.global_position) > r2:
			continue
		if require_line_of_sight and not _can_see(a, e):
			continue
		return true
	return false


func _ally_checked_spot(allies: Array, pos: Vector3) -> bool:
	var r2 := clear_radius * clear_radius
	for a in allies:
		if a.global_position.distance_squared_to(pos) <= r2:
			return true
	return false


func _make_marker() -> Label3D:
	var l := Label3D.new()
	l.text = marker_text
	l.font_size = 64
	l.pixel_size = 0.03                       # 64 * 0.03 = about 1.9 m tall
	l.outline_size = 14
	l.outline_modulate = Color.BLACK
	l.modulate = marker_color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true                    # visible through rocks and cliffs
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.visible = false
	add_child(l)
	return l


# Fallback only (no fog node): can ally "a" see enemy "e"? Rocks/cliffs block, other vehicles don't.
func _can_see(a: Node3D, e: Node3D) -> bool:
	var space := get_tree().root.world_3d.direct_space_state
	_query.from = a.global_position + Vector3.UP
	_query.to = e.global_position + Vector3.UP
	var exclude: Array[RID] = []
	if a is CollisionObject3D:
		exclude.append(a.get_rid())
	if e is CollisionObject3D:
		exclude.append(e.get_rid())
	for i in 3:
		_query.exclude = exclude
		var hit := space.intersect_ray(_query)
		if hit.is_empty():
			return true
		var c = hit.collider
		if c is Node and c.get("faction") != null:
			exclude.append(hit.rid)
			continue
		return false
	return false


# guesses at common "dead" variables, since the real one lives in VehicleBase
func _is_dead(u: Object) -> bool:
	for p in ["is_dead", "dead", "destroyed"]:
		var val = u.get(p)
		if val is bool and val:
			return true
	var hp = u.get("health")
	return (hp is float or hp is int) and hp <= 0.0
