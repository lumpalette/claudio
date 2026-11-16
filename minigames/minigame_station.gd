class_name MinigameStation
extends Interactable

@export var action_id: String
@export var minigame_scene: PackedScene

var _game: Minigame


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

	var layer := CanvasLayer.new()   # para que la cámara no lo mueva
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(_game)
	get_tree().root.add_child(layer)
	get_tree().paused = true
	
	return true

func _on_finished(value: float) -> void:
	var layer := _game.get_parent()
	_game = null
	get_tree().paused = false
	layer.queue_free()
	GameState.finish_minigame(action_id, value)
	interaction_ended.emit()
