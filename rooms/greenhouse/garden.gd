extends Interactable
## Huerto: sembrar, ver el progreso y cosechar.

## Dónde se dibuja el letrero del cultivo (coordenadas globales).
@export var status_position := Vector2(20, 150)

var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.add_theme_font_override("font", preload("res://shared/fonts/press_start_2p_regular.ttf"))
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.top_level = true
	_label.z_index = 50
	add_child(_label)
	_label.global_position = status_position
	GameState.crop_changed.connect(_update_label)
	TimeManager.time_changed.connect(_on_time_changed)
	_update_label()


func _on_time_changed(_day: int, _hour: float) -> void:
	_update_label()


func _update_label() -> void:
	if GameState.crop_type == "":
		_label.text = "Huerto vacío"
		_label.modulate = Color(0.75, 0.8, 0.85)
	elif GameState.is_crop_ready():
		_label.text = "%s: ¡lista!" % Balance.CROPS[GameState.crop_type]["name"]
		_label.modulate = Color(0.55, 1.0, 0.45)
	else:
		_label.text = "%s: %d%%" % [Balance.CROPS[GameState.crop_type]["name"], int(GameState.get_crop_progress() * 100.0)]
		_label.modulate = Color(1.0, 0.9, 0.5)


func interact(_player: Player) -> bool:
	if GameState.crop_type != "" and GameState.is_crop_ready():
		var harvested: String = GameState.crop_type
		if GameState.harvest():
			GameState.message.emit("Cosechaste %s: ve a la cocina" % Balance.CROPS[harvested]["name"])
		return false

	var hud := Hud.find(self)
	if hud == null:
		return false

	var options: Array[Dictionary] = []
	var info := ""
	if GameState.crop_type == "":
		info = "Elige qué sembrar (-%d energía)" % int(Balance.SOW_ENERGY)
		for crop_id: String in Balance.CROPS:
			var crop: Dictionary = Balance.CROPS[crop_id]
			options.append({
				"text": "%s: %dh, -%d agua" % [crop["name"], int(crop["grow_hours"]), int(crop["water"])],
				"action": GameState.sow.bind(crop_id),
			})
	else:
		var crop: Dictionary = Balance.CROPS[GameState.crop_type]
		var left: float = (1.0 - GameState.get_crop_progress()) * float(crop["grow_hours"])
		info = "%s creciendo: %d%%" % [crop["name"], int(GameState.get_crop_progress() * 100.0)]
		options.append({"text": "Faltan %.1f horas" % left, "disabled": true})

	hud.open_menu("HUERTO", options, func() -> void: interaction_ended.emit(), info)
	return true
