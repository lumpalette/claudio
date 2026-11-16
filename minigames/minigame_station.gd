class_name MinigameStation
extends Interactable

@export var action_id: String
@export var minigame_scene: PackedScene

var _game: Minigame
var _layer: CanvasLayer


func interact(_player: Player) -> bool:
	if _game:
		return false  # ya hay uno abierto
	if not GameState.start_minigame(action_id):
		return false

	var instance := minigame_scene.instantiate()
	if not (instance is Minigame):
		push_error("%s no hereda de Minigame (script: %s)" % [minigame_scene.resource_path, instance.get_script().resource_path])
		instance.queue_free()
		GameState.finish_minigame(action_id, Balance.MINIGAME_MIN_RESULT)  # no dejar el reloj pausado
		return false

	_game = instance
	_game.finished.connect(_on_finished, CONNECT_ONE_SHOT)

	# El minijuego va dentro de un SubViewport, que tiene su propio World2D.
	# Así sus colisiones no chocan con las de la sala (el rayo del minijuego
	# del agua se atoraba en las paredes de la sala de operaciones).
	#
	# Tampoco se pausa el árbol: al pausarlo, Godot apaga el servidor de
	# físicas y los minijuegos dejan de detectar colisiones (el astronauta
	# del oxígeno no atrapaba ninguna bolita). El jugador no se mueve porque
	# se queda en el estado "wait" hasta que el minijuego termina, y el reloj
	# lo pausa GameState.start_minigame().
	_layer = CanvasLayer.new()
	_layer.layer = 10
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	_layer.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width", 640),
		ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	viewport.add_child(_game)
	get_tree().root.add_child(_layer)

	return true


func _on_finished(value: float) -> void:
	_game = null
	if _layer:
		_layer.queue_free()
		_layer = null
	GameState.finish_minigame(action_id, value)
	interaction_ended.emit()
