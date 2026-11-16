extends State


@export var _this: Player


func enter() -> void:
	_this.animator.play("idle_" + Player.get_direction_name(_this.direction))


func physics_process(delta: float) -> void:
	if _this.try_interact():
		return
	
	var dir_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if dir_vector != Vector2.ZERO:
		_this.state.set_state("move")
		return

	_this.velocity = _this.velocity.move_toward(dir_vector * _this.max_speed, _this.friction * delta)
	_this.move_and_slide()
