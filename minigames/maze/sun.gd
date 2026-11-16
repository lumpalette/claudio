extends CharacterBody2D

const SPEED = 300.0

@onready var posicion_inicial: Vector2 = global_position

func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * SPEED
	move_and_slide()

	if get_slide_collision_count() > 0:
		global_position = posicion_inicial
		velocity = Vector2.ZERO
