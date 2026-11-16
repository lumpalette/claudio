extends CanvasLayer

var total_impuresas: int = 0
var collected_impuresas: int = 0

@export var start_time: float = 10.0
var time_left: float = 0.0

@onready var impuresas_label: Label = $Label
@onready var timer_label: Label = $LabelTimer


func _ready() -> void:
	add_to_group("contador")
	var impuresas = get_tree().get_nodes_in_group("impuresas")
	total_impuresas = impuresas.size()
	_update_label_impuresas()
	time_left = start_time


func _process(delta: float) -> void:
	if time_left <= 0.0:
		# hack marranisimo pero jala creo
		get_parent().finished.emit(1)
		get_parent().queue_free()
		return

	time_left -= delta
	time_left = max(time_left, 0.0)
	timer_label.text = "%.2f" % time_left


func _update_label_impuresas() -> void:
	impuresas_label.text = "%d / %d" % [collected_impuresas, total_impuresas]


func impuresa_collected() -> void:
	collected_impuresas += 1
	_update_label_impuresas()
	
	if collected_impuresas >= 5:
		get_parent().finished.emit(1)
		get_parent().queue_free()
