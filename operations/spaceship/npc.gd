extends CharacterBody2D

@export var speed: float = 200.0

@onready var sprite: Sprite2D = $Sprite2D

func _physics_process(_delta: float) -> void:
	var direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * speed

	if direction.x != 0:
		sprite.flip_h = direction.x < 0

	move_and_slide()
