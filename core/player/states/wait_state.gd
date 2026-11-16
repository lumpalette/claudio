extends State


@export var _this: Player


func enter() -> void:
	_this.velocity = Vector2.ZERO
	_this.animator.play("idle_" + Player.get_direction_name(_this.direction))
	if _this.current_interaction:
		_this.current_interaction.interaction_ended.connect(_on_interaction_ended, CONNECT_ONE_SHOT)
	else:
		_this.state.set_state.call_deferred("idle")


func exit() -> void:
	var target := _this.current_interaction
	if is_instance_valid(target) and target.interaction_ended.is_connected(_on_interaction_ended):
		target.interaction_ended.disconnect(_on_interaction_ended)
	_this.current_interaction = null


func _on_interaction_ended() -> void:
	_this.state.set_state("idle")
