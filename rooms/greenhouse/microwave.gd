extends Interactable


func interact(player: Player) -> bool:
	GameState.eat("")
	return true
