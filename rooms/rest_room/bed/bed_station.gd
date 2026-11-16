extends Interactable
## Cama: de noche duerme hasta las 06:00; de día toma una siesta.


func interact(_player: Player) -> bool:
	if not GameState.can_sleep():
		return false
	var hud := Hud.find(self)
	if hud == null:
		GameState.sleep()
		return false
	hud.play_sleep(func() -> void: interaction_ended.emit())
	return true
