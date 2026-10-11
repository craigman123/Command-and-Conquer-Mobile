extends DirectionalLight3D

# ---------- SHADOW SETTINGS (true = casts a shadow, false = no shadow) ----------
@export var sun_shadows := true      # master switch: false turns ALL shadows off

@export var trees_shadow := false
@export var flora_shadow := false    # grass, bushes, cactus
@export var rocks_shadow := false
@export var signs_shadow := false
@export var cliffs_shadow := true
@export var wrecks_shadow := true
# --------------------------------------------------------------------------------


func _ready() -> void:
	shadow_enabled = sun_shadows
	if not sun_shadows:
		return                          # nothing to sort out if the sun has no shadows

	await get_tree().process_frame      # let the map finish loading

	# folder name in your Scene dock -> its setting
	var settings := {
		"Trees": trees_shadow,
		"Flora": flora_shadow,
		"Rocks": rocks_shadow,
		"Signs": signs_shadow,
		"Cliffs": cliffs_shadow,
		"Wrecks": wrecks_shadow,
	}

	var scene := get_tree().current_scene
	for folder_name in settings:
		var folder := scene.find_child(folder_name, true, false)
		if folder == null:
			push_warning("Shadow script: folder '%s' not found" % folder_name)
			continue
		_set_shadows(folder, settings[folder_name])


func _set_shadows(root: Node, casts_shadow: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if root is GeometryInstance3D:
		root.cast_shadow = mode
	for mesh in root.find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = mode
