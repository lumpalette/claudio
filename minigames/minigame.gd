class_name Minigame
extends Node2D


@warning_ignore("unused_signal")
signal finished(value: float)

var _has_finished := false


## Emite `finished` una sola vez (llamadas repetidas se ignoran).
## MinigameStation se encarga de cerrar la ventana del minijuego.
func finish(value: float) -> void:
	if _has_finished:
		return
	_has_finished = true
	finished.emit(value)


## Busca el Minigame dueño de `node` (la raíz de la escena del minijuego).
## Así los nodos hijos no dependen de get_parent(), que se rompe si cambias
## la jerarquía en el editor.
static func of(node: Node) -> Minigame:
	var current := node
	while current:
		if current is Minigame:
			return current
		current = current.get_parent()
	return null
