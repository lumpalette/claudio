extends CanvasLayer

@export var start_time: float = 15.0
var time_left: float = 0.0
var _terminado: bool = false
var timer_label: Label

func _ready() -> void:
	var labels := find_children("*", "Label", true, false)
	if labels.size() > 0:
		timer_label = labels[0]
	else:
		push_error("No hay ningún Label guardado dentro de temporizador sun.tscn")
		return

	time_left = start_time
	timer_label.text = "%.2f" % time_left

func _process(delta: float) -> void:
	if _terminado or timer_label == null:
		return

	if time_left <= 0.0:
		_terminado = true
		_acabarse_el_tiempo()
		return

	time_left -= delta
	time_left = max(time_left, 0.0)
	timer_label.text = "%.2f" % time_left

func _acabarse_el_tiempo() -> void:
	var game := Minigame.of(self)
	if game == null:
		push_error("Temporizador del laberinto: no está dentro de un Minigame")
	elif game.has_method("terminar_minijuego"):
		game.terminar_minijuego(0.5)
	else:
		game.finish(0.5)
