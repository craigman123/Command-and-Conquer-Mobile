class_name CombatVFX
extends RefCounted

# Everything is built ONCE and reused. Nothing is created from scratch during a fight.

static var warmed := false
static var _defs := {}          # effect name -> its settings
static var _templates := {}     # effect name -> {pm, mesh} (built once)
static var _free := {}          # effect name -> list of idle particle nodes, ready to reuse
static var _light: OmniLight3D
static var _light_tw: Tween
static var _puff: GradientTexture2D
static var _tracer_mesh: BoxMesh
static var _burnt: StandardMaterial3D


# ---------- settings for every effect ----------
static func _setup_defs():
	if not _defs.is_empty():
		return
	_defs = {
		"muzzle": {amount = 6, life = 0.12,
			c0 = Color(1, 0.9, 0.5, 1), c1 = Color(1, 0.4, 0.1, 1),
			speed = Vector2(2, 5), size = Vector2(0.3, 0.6), grow = 0.3,
			gravity = Vector3.ZERO, dir = Vector3(0, 0, -1), spread = 25.0, additive = true},
		"impact_sparks": {amount = 8, life = 0.3,
			c0 = Color(1, 0.8, 0.4, 1), c1 = Color(0.6, 0.3, 0.1, 1),
			speed = Vector2(2, 5), size = Vector2(0.08, 0.18), grow = 0.5,
			gravity = Vector3(0, -9, 0), dir = Vector3.UP, spread = 70.0, additive = true},
		"impact_dust": {amount = 4, life = 0.5,
			c0 = Color(0.6, 0.5, 0.4, 0.6), c1 = Color(0.4, 0.4, 0.4, 0.0),
			speed = Vector2(0.5, 1.5), size = Vector2(0.5, 0.9), grow = 2.0,
			gravity = Vector3(0, 0.5, 0), dir = Vector3.UP, spread = 60.0, additive = false},
		"explosion_fire": {amount = 20, life = 0.9,
			c0 = Color(1, 0.85, 0.4, 1), c1 = Color(0.9, 0.25, 0.05, 1),
			speed = Vector2(2, 6), size = Vector2(2.5, 4.0), grow = 1.6,
			gravity = Vector3(0, 1.5, 0), dir = Vector3.UP, spread = 60.0, additive = true},
		"explosion_smoke": {amount = 16, life = 3.0,
			c0 = Color(0.25, 0.25, 0.25, 0.8), c1 = Color(0.5, 0.5, 0.5, 0.0),
			speed = Vector2(1, 3), size = Vector2(3, 5), grow = 1.8,
			gravity = Vector3(0, 1.2, 0), dir = Vector3.UP, spread = 45.0, additive = false},
		"explosion_sparks": {amount = 30, life = 1.0,
			c0 = Color(1, 0.9, 0.5, 1), c1 = Color(1, 0.4, 0.1, 1),
			speed = Vector2(6, 14), size = Vector2(0.1, 0.2), grow = 0.3,
			gravity = Vector3(0, -12, 0), dir = Vector3.UP, spread = 180.0, additive = true},
		"wreck_smoke": {amount = 12, life = 2.5, continuous = true,
			c0 = Color(0.15, 0.15, 0.15, 0.7), c1 = Color(0.4, 0.4, 0.4, 0.0),
			speed = Vector2(0.5, 1.2), size = Vector2(1.5, 2.5), grow = 2.0,
			gravity = Vector3(0, 1.0, 0), dir = Vector3.UP, spread = 20.0, additive = false},
	}


static func _puff_texture() -> GradientTexture2D:
	if _puff == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
		_puff = GradientTexture2D.new()
		_puff.gradient = g
		_puff.fill = GradientTexture2D.FILL_RADIAL
		_puff.fill_from = Vector2(0.5, 0.5)
		_puff.fill_to = Vector2(0.5, 0.0)
		_puff.width = 64
		_puff.height = 64
	return _puff


# The expensive part (materials, curves, gradients). Runs once per effect, then is reused.
static func _template(key: String) -> Dictionary:
	if _templates.has(key):
		return _templates[key]
	_setup_defs()
	var d = _defs[key]

	var pm := ParticleProcessMaterial.new()
	pm.direction = d.dir
	pm.spread = d.spread
	pm.initial_velocity_min = d.speed.x
	pm.initial_velocity_max = d.speed.y
	pm.gravity = d.gravity
	pm.scale_min = d.size.x
	pm.scale_max = d.size.y

	var sc := Curve.new()
	sc.min_value = 0.0
	sc.max_value = maxf(d.grow, 1.0)
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(1.0, d.grow))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct

	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([d.c0, d.c0.lerp(d.c1, 0.5), Color(d.c1.r, d.c1.g, d.c1.b, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _puff_texture()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	if d.additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = mat

	_templates[key] = {pm = pm, mesh = quad}
	return _templates[key]


static func _make_node(key: String, one_shot: bool) -> GPUParticles3D:
	var t := _template(key)
	var d = _defs[key]
	var ps := GPUParticles3D.new()
	ps.amount = d.amount
	ps.lifetime = d.life
	ps.one_shot = one_shot
	ps.explosiveness = 1.0 if one_shot else 0.0
	ps.local_coords = false
	ps.emitting = false
	ps.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 20, 60))
	ps.process_material = t.pm      # the SAME material is shared by every node of this effect
	ps.draw_pass_1 = t.mesh
	return ps


static func _root(ctx: Node) -> Node:
	return ctx.get_tree().root


# When a burst finishes, its node goes back on the "idle" list so it can be reused.
static func _release(key: String, ps: GPUParticles3D):
	if not _free.has(key):
		_free[key] = []
	if not _free[key].has(ps):
		_free[key].append(ps)


# Plays one burst. Takes an idle node if there is one, only creates a new one if not.
static func _play(ctx: Node, key: String, pos: Vector3, look_dir := Vector3.ZERO):
	if not _free.has(key):
		_free[key] = []
	var ps: GPUParticles3D
	if _free[key].is_empty():
		ps = _make_node(key, true)
		ps.finished.connect(_release.bind(key, ps))
		_root(ctx).add_child(ps)
	else:
		ps = _free[key].pop_back()
	ps.global_position = pos
	if look_dir != Vector3.ZERO:
		ps.look_at(pos + look_dir, Vector3.UP)
	ps.restart()


# One light, made once and reused for every flash.
static func _flash(ctx: Node, pos: Vector3, color: Color, energy: float, light_range: float, time: float):
	if _light == null or not is_instance_valid(_light):
		_light = OmniLight3D.new()
		_light.light_energy = 0.0
		_root(ctx).add_child(_light)
	if _light_tw and _light_tw.is_valid():
		_light_tw.kill()
	_light.global_position = pos
	_light.light_color = color
	_light.omni_range = light_range
	_light.light_energy = energy
	_light_tw = _light.create_tween()
	_light_tw.tween_property(_light, "light_energy", 0.0, time)


# ---------- the effects the game calls ----------
static func muzzle_flash(ctx: Node, pos: Vector3, dir: Vector3):
	_play(ctx, "muzzle", pos, dir)
	_flash(ctx, pos, Color(1, 0.7, 0.3), 3.0, 6.0, 0.08)


static func tracer(ctx: Node, from: Vector3, to: Vector3):
	var dist := from.distance_to(to)
	if dist < 0.5:
		return
	if _tracer_mesh == null:
		_tracer_mesh = BoxMesh.new()
		_tracer_mesh.size = Vector3(0.07, 0.07, 2.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(2.5, 1.8, 0.8)
		_tracer_mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	_root(ctx).add_child(mi)
	mi.global_position = from
	mi.look_at(to, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", to, dist / 150.0)
	tw.tween_callback(mi.queue_free)


static func impact(ctx: Node, pos: Vector3):
	_play(ctx, "impact_sparks", pos)
	_play(ctx, "impact_dust", pos)


static func explosion(ctx: Node, pos: Vector3):
	_play(ctx, "explosion_fire", pos)
	_play(ctx, "explosion_smoke", pos + Vector3.UP * 0.5)
	_play(ctx, "explosion_sparks", pos)
	_flash(ctx, pos + Vector3.UP, Color(1, 0.6, 0.25), 12.0, 20.0, 0.4)


# Continuous smoke from the wreck. It belongs to the vehicle, so it goes away with it.
static func wreck_smoke(vehicle: Node3D, pos: Vector3):
	var ps := _make_node("wreck_smoke", false)
	vehicle.add_child(ps)
	ps.global_position = pos
	ps.emitting = true


# The charred look. One shared material for every wreck.
static func burnt_material() -> StandardMaterial3D:
	if _burnt == null:
		_burnt = StandardMaterial3D.new()
		_burnt.albedo_color = Color(0.04, 0.035, 0.03, 0.8)
		_burnt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _burnt


# ---------- the secret rehearsal ----------
# Plays every effect once, right in front of the camera, for two frames. This is when the
# engine compiles all the shaders, so the first real explosion has nothing left to compile.
static func warm_up(ctx: Node):
	_setup_defs()
	var cam := ctx.get_viewport().get_camera_3d()
	var pos := Vector3.ZERO
	if cam:
		pos = cam.global_position - cam.global_transform.basis.z * 4.0

	var items := []
	for key in _defs.keys():
		var cont: bool = _defs[key].get("continuous", false)
		var ps := _make_node(key, not cont)
		if not cont:
			ps.finished.connect(_release.bind(key, ps))
		_root(ctx).add_child(ps)
		ps.global_position = pos
		ps.emitting = true
		items.append([key, ps, cont])

	# also rehearse the charred overlay, which is a different shader from the normal paint
	var dummy := MeshInstance3D.new()
	dummy.mesh = BoxMesh.new()
	dummy.material_overlay = burnt_material()
	_root(ctx).add_child(dummy)
	dummy.global_position = pos

	await ctx.get_tree().process_frame
	await ctx.get_tree().process_frame

	dummy.queue_free()
	for it in items:
		var ps: GPUParticles3D = it[1]
		ps.emitting = false
		if it[2]:
			ps.queue_free()
		else:
			_release(it[0], ps)
