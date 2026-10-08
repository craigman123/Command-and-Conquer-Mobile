extends MeshInstance3D

const MAX_UNITS := 32
const RAYS := 96

@export var map_min := Vector2(-100, -100)   		# world X,Z of the map's top-left corner
@export var map_size := Vector2(200, 200)    		# map size in meters
@export var resolution := 512                		# texture pixels per side (explored trail)
@export var vision_radius := 15.0            		# default vision in meters
@export var ground_y := 0.0                  		# world Y of the flat ground level
@export_flags_3d_physics var blocker_mask := 128    # physics layer 8 blocks sight
@export var eye_height := 1.5                		# height the rays travel at
@export var los_interval := 0.1              		# seconds between raycast updates
@export var wall_reveal := 0.5       				# small margin past the wall's far face
@export var wall_max_depth := 3.0    				# max wall thickness to light up (meters)
@export var explore_wall_margin := 2.5   			# explored stops this far past the wall's front face
@export var wall_heights := PackedFloat32Array([4.0, 8.0, 14.0])
#var _explore_los := PackedByteArray()

@export var blocker_roots: Array[NodePath] = [
	^"../NavigationRegion3D/Environment/Cliffs",
	^"../NavigationRegion3D/Environment/Rocks",
]

var _visible := PackedByteArray()
var _explored := PackedByteArray()
var _vis_img: Image
var _exp_img: Image
var _vis_tex: ImageTexture
var _exp_tex: ImageTexture

var _los_data := PackedByteArray()
var _los_img: Image
var _los_tex: ImageTexture
var _los_timer := 0.0
var _cast_units: Array = []
var _cast_info := PackedVector4Array()


func _ready() -> void:
	_apply_episode_bounds()

	_visible.resize(resolution * resolution)
	_explored.resize(resolution * resolution)
	_visible.fill(0)
	_explored.fill(0)
	_vis_img = Image.create_from_data(resolution, resolution, false, Image.FORMAT_L8, _visible)
	_exp_img = Image.create_from_data(resolution, resolution, false, Image.FORMAT_L8, _explored)
	_vis_tex = ImageTexture.create_from_image(_vis_img)
	_exp_tex = ImageTexture.create_from_image(_exp_img)

	# Full-screen overlay quad (the shader ignores the transform)
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh = quad
	extra_cull_margin = 16384.0
	visible = true

	var mat := material_override as ShaderMaterial
	mat.set_shader_parameter("visible_tex", _vis_tex)
	mat.set_shader_parameter("explored_tex", _exp_tex)
	mat.set_shader_parameter("map_min", map_min)
	mat.set_shader_parameter("map_size", map_size)
	mat.set_shader_parameter("ground_y", ground_y)

	_los_data.resize(RAYS * MAX_UNITS)
	_los_data.fill(255)
	_los_img = Image.create_from_data(RAYS, MAX_UNITS, false, Image.FORMAT_L8, _los_data)
	_los_tex = ImageTexture.create_from_image(_los_img)
	mat.set_shader_parameter("los_tex", _los_tex)
	_los_timer = los_interval

	var made := _ensure_blockers()
	var bodies := get_tree().root.find_children("*", "StaticBody3D", true, false).size()
	print("fog: colliders created=", made, "  static bodies in scene=", bodies)


func _apply_episode_bounds() -> void:
	var session = get_node_or_null("/root/GameSession")
	if session == null:
		print("fog: no /root/GameSession autoload -> using Inspector values")
		return
	var ep = session.get("selected_episode")
	if not (ep is Dictionary) or ep.is_empty():
		print("fog: GameSession has no episode -> using Inspector values")
		return
	var fmin = ep.get("fog_min_size", null)
	var fmax = ep.get("fog_max_size", null)
	if fmin is Array and fmax is Array and fmin.size() == 2 and fmax.size() == 2:
		map_min = Vector2(fmin[0], fmin[1])
		map_size = Vector2(fmax[0] - fmin[0], fmax[1] - fmin[1])
		print("fog: applied min=", map_min, " size=", map_size)
	else:
		print("fog: JSON values missing or not [x, y] arrays -> using Inspector values")


# Makes sure every mesh under the blocker roots has a collider on the blocker layer.
func _ensure_blockers() -> int:
	var made := 0
	for path in blocker_roots:
		var root := get_node_or_null(path)
		if root == null:
			push_warning("fog: blocker root not found: " + str(path))
			continue
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var has_body := false
			for c in mi.get_children():
				if c is StaticBody3D:
					has_body = true
					c.collision_layer |= blocker_mask
			if not has_body:
				mi.create_trimesh_collision()
				for c in mi.get_children():
					if c is StaticBody3D:
						c.collision_layer = blocker_mask
						c.collision_mask = 0
						made += 1
	return made


func _process(_delta: float) -> void:
	_push_units()


func _physics_process(delta: float) -> void:
	_los_timer += delta
	if _los_timer >= los_interval:
		_los_timer = 0.0
		_cast_all()


func _cast_all() -> void:
	var space := get_world_3d().direct_space_state
	_cast_units = get_tree().get_nodes_in_group("player_units").slice(0, MAX_UNITS)
	_cast_info = PackedVector4Array()
	_cast_info.resize(_cast_units.size())
	_los_data.fill(255)

	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = blocker_mask

	for n in _cast_units.size():
		var unit = _cast_units[n]
		var p: Vector3 = unit.global_position
		var v = unit.get("vision_range")
		var radius: float = vision_radius if v == null else float(v)
		_cast_info[n] = Vector4(p.x, p.z, radius, 0.0)

		for r in RAYS:
			var a := TAU * (r + 0.5) / RAYS - PI
			var dir := Vector3(cos(a), 0, sin(a))

			# Low ray decides whether this direction is blocked at all
			var origin := p + Vector3(0, eye_height, 0)
			q.from = origin
			q.to = origin + dir * radius
			var hit := space.intersect_ray(q)
			var d := radius

			if not hit.is_empty():
				var first := Vector2(hit.position.x - p.x, hit.position.z - p.z).length()
				var far := first

				# Higher rays follow the wall up its slope; only trust hits near the first one
				for h in wall_heights:
					var o := p + Vector3(0, h, 0)
					q.from = o
					q.to = o + dir * radius
					var hh := space.intersect_ray(q)
					if hh.is_empty():
						continue
					var dist := Vector2(hh.position.x - p.x, hh.position.z - p.z).length()
					if dist <= first + wall_max_depth:
						far = maxf(far, dist)

				d = minf(far + wall_reveal, radius)
			_los_data[n * RAYS + r] = int(clampf(d / radius, 0.0, 1.0) * 255.0)

	_los_img.set_data(RAYS, MAX_UNITS, false, Image.FORMAT_L8, _los_data)
	_los_tex.update(_los_img)
	_update_fog()


func _push_units() -> void:
	var arr := PackedVector4Array()
	arr.resize(MAX_UNITS)
	var count := _cast_info.size()
	for i in count:
		arr[i] = _cast_info[i]
	var mat := material_override as ShaderMaterial
	mat.set_shader_parameter("units", arr)
	mat.set_shader_parameter("unit_count", count)


func _update_fog() -> void:
	_visible.fill(0)
	for n in _cast_info.size():
		var info := _cast_info[n]
		var radius := info.z
		var rx := radius / map_size.x * resolution
		var ry := radius / map_size.y * resolution
		var cx := int((info.x - map_min.x) / map_size.x * resolution)
		var cy := int((info.y - map_min.y) / map_size.y * resolution)
		for y in range(maxi(cy - int(ceil(ry)), 0), mini(cy + int(ceil(ry)) + 1, resolution)):
			for x in range(maxi(cx - int(ceil(rx)), 0), mini(cx + int(ceil(rx)) + 1, resolution)):
				var dx := (x - cx) / rx
				var dy := (y - cy) / ry
				var d2 := dx * dx + dy * dy
				if d2 > 1.0:
					continue
				var idx := int((atan2(dy, dx) + PI) / TAU * RAYS) % RAYS
				var lim := _los_data[n * RAYS + idx] / 255.0 * radius
				var dist := sqrt(d2) * radius
				if dist <= lim:
					var i := y * resolution + x
					_visible[i] = 255
					if dist <= lim - 2.0:
						_explored[i] = 255                             # only if not behind a wall
	_vis_img.set_data(resolution, resolution, false, Image.FORMAT_L8, _visible)
	_exp_img.set_data(resolution, resolution, false, Image.FORMAT_L8, _explored)
	_vis_tex.update(_vis_img)
	_exp_tex.update(_exp_img)


func is_visible_at(world_pos: Vector3) -> bool:
	var x := int((world_pos.x - map_min.x) / map_size.x * resolution)
	var y := int((world_pos.z - map_min.y) / map_size.y * resolution)
	if x < 0 or y < 0 or x >= resolution or y >= resolution:
		return false
	return _visible[y * resolution + x] > 0
	
#func _wall_far_dist(space: PhysicsDirectSpaceState3D, hit: Dictionary, dir: Vector3, p: Vector3) -> float:
	#var back := PhysicsRayQueryParameters3D.new()
	#back.collision_mask = blocker_mask
	#back.hit_back_faces = true
	#back.from = hit.position + dir * wall_max_depth
	#back.to = hit.position + dir * 0.05
	#var skip: Array[RID] = []
	#for i in 4:
		#back.exclude = skip
		#var h := space.intersect_ray(back)
		#if h.is_empty():
			#break
		#if h.collider == hit.collider:
			#return Vector2(h.position.x - p.x, h.position.z - p.z).length()
		#skip.append(h.rid)   # some other object in the way, ignore it and retry
	## far side not found, so use the max depth
	#return Vector2(hit.position.x - p.x, hit.position.z - p.z).length() + wall_max_depth
