class_name CameraController
extends Camera2D


@export var speed: float
@export var target: Node2D

@export var target_position: Vector2:
	set(value):
		target_position = value
		target = null


func _physics_process(delta: float) -> void:
	var pos: Vector2
	
	if target:
		pos = target.position
	else:
		pos = target_position
	
	position = position.move_toward(pos, speed * delta)
