extends Interactable
## Cocina: elige qué comer. La comida empacada se calienta (cuesta energía y
## sube el bienestar); lo cosechado se come fresco.


func interact(_player: Player) -> bool:
	var hud := Hud.find(self)
	if hud == null:
		return _eat_first_available()

	var options: Array[Dictionary] = []
	for food_id: String in Balance.FOODS:
		var count: int = GameState.get_food_count(food_id)
		if count <= 0:
			continue
		var food: Dictionary = Balance.FOODS[food_id]
		var text := "%s x%d (+%d)" % [food["name"], count, int(food["satiety"])]
		if food["heatable"]:
			text = "Calentar " + text
		options.append({"text": text, "action": GameState.eat.bind(food_id, food["heatable"])})

	if options.is_empty():
		GameState.message.emit("No tienes comida. Cosecha en el huerto")
		return false

	hud.open_menu("COCINA", options, func() -> void: interaction_ended.emit(),
		"Saciedad: %d  -  %s" % [int(GameState.get_stat(Balance.SATIETY)), GameState.get_satiety_state()])
	return true


func _eat_first_available() -> bool:
	for food_id: String in Balance.FOODS:
		if GameState.get_food_count(food_id) > 0:
			GameState.eat(food_id, Balance.FOODS[food_id]["heatable"])
			return false
	GameState.message.emit("No tienes comida")
	return false
