extends Node

@export var fog: NodePath = ^"../FogOfWar"
@export var roots: Array[NodePath] = [
	^"../NavigationRegion3D/Environment/Trees",
	^"../NavigationRegion3D/Environment/Flora",   # includes Cacti and Bushes
]
@export var margin := 3.0            # a prop shows when ground this close to its base is visible
@export var show_explored := false   # true = props stay visible in explored (grey) areas
@export var check_interval := 0.15
@export var max_size := 12.0         # ignore meshes wider than this (large pieces)

const OFFSETS := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]

var _fog: Node
var _meshes: Array = []
var _bases := PackedVector3Array()
var _state := PackedByteArray()
var _timer := 0.0


func _ready() -> void:
	_fog = get_node_or_null(fog)
	if _fog == null:
		push_warning("prop_hider: fog node not found")
		set_process(false)
		return
	for path in roots:
		var root := get_node_or_null(path)
		if root == null:
			push_warning("prop_hider: root not found: " + str(path))
			continue
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			if not mi.visible:
				continue
			var box: AABB = mi.global_transform * mi.get_aabb()
			if maxf(box.size.x, box.size.z) > max_size:
				continue
			var c := box.get_center()
			c.y = box.position.y                  # base of the prop
			_meshes.append(mi)
			_bases.append(c)
			mi.visible = false                     # start hidden, shown once seen
	_state.resize(_meshes.size())
	_state.fill(0)
	_timer = check_interval
	print("prop_hider: managing ", _meshes.size(), " meshes")
	LoadStatus.report("Optimizing the map: %d meshes managed" % _meshes.size())


func _process(delta: float) -> void:
	_timer += delta
	if _timer < check_interval:
		return
	_timer = 0.0
	for i in _meshes.size():
		var mi = _meshes[i]
		if not is_instance_valid(mi):
			continue
		var vis := _seen(_bases[i])
		if vis != (_state[i] == 1):
			_state[i] = 1 if vis else 0
			mi.visible = vis


func _seen(p: Vector3) -> bool:
	if _fog.is_visible_at(p):
		return true
	if margin > 0.0:
		for o in OFFSETS:
			if _fog.is_visible_at(p + o * margin):
				return true
	if show_explored and _fog.has_method("is_explored_at"):
		if _fog.is_explored_at(p):
			return true
		for o in OFFSETS:
			if _fog.is_explored_at(p + o * margin):
				return true
	return false
