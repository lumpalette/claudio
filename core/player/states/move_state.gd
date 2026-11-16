extends State


@export var _this: Player


func enter() -> void:
	_this.animator.play("move_" + Player.get_direction_name(_this.direction))


func physics_process(delta: float) -> void:
	if _this.try_interact():
		return

	var dir_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if dir_vector == Vector2.ZERO:
		_this.state.set_state("idle")
		return

	_this.direction = Player.get_direction_from_vector(dir_vector, 0.2, _this.direction)
	_this.velocity = _this.velocity.move_toward(dir_vector * _this.max_speed, _this.acceleration * delta)
	_this.move_and_slide()

	_this.animator.play("move_" + Player.get_direction_name(_this.direction))
