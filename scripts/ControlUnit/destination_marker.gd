class_name DestinationMarker
extends Node3D

@export var color := Color(0.1, 1.0, 0.2)
@export var lifetime := 1.2

func _ready() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.4
	disc.bottom_radius = 0.4
	disc.height = 0.05

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var mesh := MeshInstance3D.new()
	mesh.mesh = disc
	mesh.material_override = mat
	add_child(mesh)

	scale = Vector3.ONE * 0.5
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE * 1.5, lifetime)
	tween.tween_property(mat, "albedo_color:a", 0.0, lifetime)
	tween.chain().tween_callback(queue_free)
