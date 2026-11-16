class_name CropMenu
extends CanvasLayer
## Menú para elegir qué sembrar en una maceta. Lo abre PlantPot con open().
##
## Los botones se crean a partir de Balance.CROPS (no hay cultivos escritos
## aquí) y sembrar pasa por GameState.sow(). Mientras está abierto pausa el
## reloj con el motivo &"menu". Esc o "Cerrar" lo cierran.

## Se emite al cerrarse (el jugador vuelve a moverse).
signal closed()

const FONT := preload("res://shared/fonts/press_start_2p_regular.ttf")
const COLOR_ACCENT := Color(0.30, 0.88, 0.95)
const COLOR_TEXT := Color(0.88, 0.95, 1.0)
const COLOR_DISABLED := Color(0.45, 0.50, 0.55)
const COLOR_PANEL := Color(0.03, 0.07, 0.11, 0.94)

## Maceta que se está sembrando (-1 = menú cerrado).
var plot := -1

var _title: Label
var _options: VBoxContainer
var _close_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func open(target_plot: int) -> void:
	plot = target_plot
	_title.text = "Maceta %d: ¿qué sembrar?" % (plot + 1)
	_fill_options()
	visible = true
	get_tree().paused = true
	TimeManager.pause_clock(&"menu")
	_focus_first_button()


func close() -> void:
	if not visible:
		return
	visible = false
	plot = -1
	get_tree().paused = false
	TimeManager.resume_clock(&"menu")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_crop_chosen(type: Balance.CropType) -> void:
	var target := plot
	close()
	GameState.sow(target, type)


# --- Construcción de la interfaz -------------------------------------------

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.border_color = COLOR_ACCENT
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_title = Label.new()
	_style_label(_title, COLOR_ACCENT)
	box.add_child(_title)

	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 4)
	box.add_child(_options)

	_close_button = _make_button("Cerrar")
	_close_button.pressed.connect(close)
	box.add_child(_close_button)


## Un botón por cultivo: "Lechuga 12h agua:1 da:3".
## Se desactiva si la estación no tiene la energía y el agua para sembrarlo.
func _fill_options() -> void:
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()

	for type: Balance.CropType in Balance.CROPS:
		var crop: Dictionary = Balance.CROPS[type]
		var button := _make_button("%s %dh agua:%d da:%d" % [
			crop["name"], int(crop["grow_hours"]), int(crop["water"]), int(crop["yield"])])
		button.disabled = not GameState.can_afford({
			Balance.STATION_ENERGY: Balance.SOW_ENERGY,
			Balance.STATION_WATER: crop["water"],
		})
		button.pressed.connect(_on_crop_chosen.bind(type))
		_options.add_child(button)


func _focus_first_button() -> void:
	for button: Button in _options.get_children():
		if not button.disabled:
			button.grab_focus()
			return
	_close_button.grab_focus()


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 8)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_focus_color", COLOR_ACCENT)
	button.add_theme_color_override("font_hover_color", COLOR_ACCENT)
	button.add_theme_color_override("font_disabled_color", COLOR_DISABLED)
	return button


func _style_label(label: Label, color: Color) -> void:
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
