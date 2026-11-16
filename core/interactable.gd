class_name Interactable
extends Area2D


signal interaction_ended


@export var prompt: String = "Interactuar"


## Devuelve true si el jugador debe esperar a interaction_ended.
## Devuelve false si fue instantánea (beber, filtrar) o si no se pudo hacer.
func interact(player: Player) -> bool:
	return false
