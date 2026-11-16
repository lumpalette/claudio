extends Minigame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		terminar_minijuego(0.5)


func terminar_minijuego(result: float) -> void:
	if _has_finished:
		return
	result = clampf(result, 0.5, 1.0)
	print("Laberinto terminado con resultado: ", result)
	finish(result)
