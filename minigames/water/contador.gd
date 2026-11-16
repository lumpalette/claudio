extends CanvasLayer

## Impurezas que hay que juntar para ganar con resultado 1.0.
@export var impuresas_para_ganar: int = 5
@export var start_time: float = 10.0

var total_impuresas: int = 0
var collected_impuresas: int = 0
var time_left: float = 0.0
var _terminado := false

@onready var impuresas_label: Label = $Label
@onready var timer_label: Label = $LabelTimer


func _ready() -> void:
	add_to_group("contador")
	total_impuresas = get_tree().get_nodes_in_group("impuresas").size()
	_update_label_impuresas()
	time_left = start_time


func _process(delta: float) -> void:
	if _terminado:
		return

	time_left = maxf(time_left - delta, 0.0)
	timer_label.text = "%.2f" % time_left

	if time_left <= 0.0:
		# Se acabó el tiempo: el resultado depende de cuántas juntó.
		var meta := maxi(mini(impuresas_para_ganar, total_impuresas), 1)
		_terminar(float(collected_impuresas) / meta)


func _update_label_impuresas() -> void:
	impuresas_label.text = "%d / %d" % [collected_impuresas, total_impuresas]


func impuresa_collected() -> void:
	if _terminado:
		return
	collected_impuresas += 1
	_update_label_impuresas()

	if collected_impuresas >= impuresas_para_ganar:
		_terminar(1.0)


func _terminar(result: float) -> void:
	_terminado = true
	var game := Minigame.of(self)
	if game:
		game.finish(clampf(result, 0.0, 1.0))
	else:
		push_error("contador: no está dentro de un Minigame")
