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
	var parent := get_parent()
	if parent.has_method("terminar_minijuego"):
		parent.terminar_minijuego(0.5)
	elif parent.has_signal("finished"):
		parent.finished.emit(0.5)
		parent.queue_free()
