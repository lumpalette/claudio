class_name StateMachine
extends Node


var _current_state: State
var _states: Dictionary[String, State]


func _ready() -> void:
	for child in get_children():
		if child is State:
			_states[child.name.to_lower()] = child
	
	set_state(get_child(0).name)


func _process(delta: float) -> void:
	if _current_state:
		_current_state.process(delta)


func _physics_process(delta: float) -> void:
	if _current_state:
		_current_state.physics_process(delta)


# Fragile asf but I don't care I'm so done with this stupid event.
func set_state(state_name: String) -> void:
	state_name = state_name.to_lower()
	
	if _current_state:
		_current_state.exit()
	
	_current_state = _states[state_name]
	
	if _current_state:
		_current_state.enter()
