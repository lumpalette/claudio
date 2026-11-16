extends CharacterBody2D

@export var speed: float = 200.0
@export var jump_velocity: float = -550.0
@export var gravity: float = 980.0

@onready var sprite: Sprite2D = $Sprite2D

func _physics_process(delta: float) -> void:
	# Aplica gravedad mientras el personaje no esté tocando el suelo
	if not is_on_floor():
		velocity.y += gravity * delta

	# Salto con Espacio / Enter (ui_accept) si está en el suelo
	if (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("move_up")) and is_on_floor():
		velocity.y = jump_velocity

	# Movimiento horizontal sin sobrescribir velocity.y
	var direction: float = Input.get_axis("move_left", "move_right")
	velocity.x = direction * speed

	if direction != 0:
		sprite.flip_h = direction < 0

	move_and_slide()
