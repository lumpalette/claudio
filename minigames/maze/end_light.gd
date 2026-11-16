extends Area2D

var _llegado: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if _llegado:
		return

	if body is CharacterBody2D:
		_llegado = true
		var game := Minigame.of(self)
		if game == null:
			push_error("end_light: no está dentro de un Minigame")
		elif game.has_method("terminar_minijuego"):
			game.terminar_minijuego(1.0)
		else:
			game.finish(1.0)
