class_name Door
extends Interactable
## Puerta entre salas. La escena principal (grupo "game") hace el cambio.


@export var target_room: StringName


func interact(_player: Player) -> bool:
	var game := get_tree().get_first_node_in_group(&"game")
	if game == null:
		GameState.message.emit("Ejecuta main.tscn para cambiar de sala")
		return false
	# Diferido: el jugador que llamó a interact() vive en la sala que se va a borrar.
	game.change_room.call_deferred(target_room)
	return false
