extends Interactable
## "Calentador de comida": calienta y come el primer alimento calentable
## que haya en el inventario.


func interact(_player: Player) -> bool:
	for food_id: String in Balance.FOODS:
		if Balance.FOODS[food_id]["heatable"] and GameState.get_food_count(food_id) > 0:
			GameState.eat(food_id, true)
			# Acción instantánea: el jugador no tiene que esperar interaction_ended.
			return false

	GameState.message.emit("No tienes comida para calentar")
	return false
