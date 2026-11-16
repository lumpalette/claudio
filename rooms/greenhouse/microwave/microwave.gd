class_name Microwave
extends Interactable
## Microondas de la cocina. Al interactuar abre el menú de comida (FoodMenu).
## La lógica de comer vive en GameState.eat_at_microwave().
##
## El origen del nodo va al pie de la mesa (para el y-sort); el área cubre
## el frente y el lado izquierdo de la mesa.

## Menú de comida que abre este microondas.
@export var food_menu: FoodMenu


func interact(_player: Player) -> bool:
	if food_menu == null:
		push_warning("Microwave: falta asignar food_menu")
		return false
	food_menu.closed.connect(_on_menu_closed, CONNECT_ONE_SHOT)
	food_menu.open()
	return true


func get_prompt() -> String:
	return "Cocinar"


func _on_menu_closed() -> void:
	interaction_ended.emit()
