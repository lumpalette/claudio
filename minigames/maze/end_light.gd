extends Area2D

var _llegado: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if _llegado:
		return

	if body is CharacterBody2D:
		_llegado = true
		var parent := get_parent()
		if parent.has_method("terminar_minijuego"):
			parent.terminar_minijuego(1.0)
		elif parent.has_signal("finished"):
			parent.finished.emit(1.0)
			parent.queue_free()
