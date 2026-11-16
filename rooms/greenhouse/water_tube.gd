extends Interactable
## Dispensador de agua: beber gasta agua de la estación y sube la hidratación.


func interact(_player: Player) -> bool:
	if GameState.drink():
		GameState.message.emit("+%d hidratación" % int(Balance.DRINK_HYDRATION))
	return false
