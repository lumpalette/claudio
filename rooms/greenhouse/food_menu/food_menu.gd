class_name FoodMenu
extends CanvasLayer
## Menú del microondas para elegir qué comer, con imágenes.
##
## Muestra una tarjeta por alimento del inventario (ícono, nombre, cantidad
## y saciedad). Comer pasa por GameState.eat_at_microwave(), que decide si se
## calienta. Arriba muestra la saciedad y la energía de la estación.
## Mientras está abierto pausa el reloj con el motivo &"menu". Esc o
## "Cerrar" lo cierran; también se cierra después de comer.
##
## Los íconos están en shared/food/<food_id>_ai.png.

## Se emite al cerrarse (el jugador vuelve a moverse).
signal closed()

const ICON_PATH := "res://shared/food/%s_ai.png"
const FONT := preload("res://shared/fonts/press_start_2p_regular.ttf")
const COLOR_ACCENT := Color(0.30, 0.88, 0.95)
const COLOR_TEXT := Color(0.88, 0.95, 1.0)
const COLOR_DIM := Color(0.55, 0.62, 0.70)
const COLOR_WARM := Color(1.0, 0.56, 0.19)
const COLOR_COLD := Color(0.55, 0.78, 1.0)
const COLOR_PANEL := Color(0.03, 0.07, 0.11, 0.94)
const COLUMNS := 3
const CARD_WIDTH := 104

var _status: Label
var _hint: Label
var _grid: GridContainer
var _empty: Label
var _close_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func open() -> void:
	_fill()
	visible = true
	get_tree().paused = true
	TimeManager.pause_clock(&"menu")
	_focus_first_button()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	TimeManager.resume_clock(&"menu")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_food_chosen(food_id: String) -> void:
	close()
	GameState.eat_at_microwave(food_id)


# --- Contenido --------------------------------------------------------------

func _fill() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	_status.text = "Saciedad %d%%   Energía %d%%" % [
		roundi(GameState.get_stat(Balance.SATIETY)),
		roundi(GameState.get_stat(Balance.STATION_ENERGY)),
	]

	var has_cold_canned := false
	for food_id: String in Balance.FOODS:
		var count := GameState.get_food_count(food_id)
		if count <= 0:
			continue
		var food: Dictionary = Balance.FOODS[food_id]
		if food["heatable"] and not GameState.can_heat(food_id):
			has_cold_canned = true
		_grid.add_child(_make_card(food_id, food, count))

	_empty.visible = _grid.get_child_count() == 0
	_grid.visible = not _empty.visible

	if GameState.is_full():
		_hint.text = "Ya estás lleno"
	elif has_cold_canned:
		_hint.text = "Sin energía: se come sin calentar"
	else:
		_hint.text = ""
	_hint.visible = _hint.text != ""


## Tarjeta: botón con el ícono, nombre, "x2 +25" y si se calienta o no.
func _make_card(food_id: String, food: Dictionary, count: int) -> Control:
	var card := VBoxContainer.new()
	card.custom_minimum_size.x = CARD_WIDTH
	card.add_theme_constant_override("separation", 2)

	var button := Button.new()
	button.custom_minimum_size = Vector2(48, 44)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var icon_path := ICON_PATH % food_id
	if ResourceLoader.exists(icon_path):
		button.icon = load(icon_path)
	else:
		button.text = "?"
	button.pressed.connect(_on_food_chosen.bind(food_id))
	card.add_child(button)

	var name_label := _make_label(food["name"], COLOR_TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = CARD_WIDTH
	card.add_child(name_label)

	card.add_child(_make_label("x%d  +%d" % [count, roundi(food["satiety"])], COLOR_ACCENT))

	if food["heatable"]:
		if GameState.can_heat(food_id):
			card.add_child(_make_label("caliente", COLOR_WARM))
		else:
			card.add_child(_make_label("frío", COLOR_COLD))
	return card


func _focus_first_button() -> void:
	for card in _grid.get_children():
		var button := card.get_child(0) as Button
		if button:
			button.grab_focus()
			return
	_close_button.grab_focus()


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

	box.add_child(_make_label("Microondas: ¿qué comer?", COLOR_ACCENT))
	_status = _make_label("", COLOR_DIM)
	box.add_child(_status)
	_hint = _make_label("", COLOR_WARM)
	box.add_child(_hint)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 8)
	box.add_child(_grid)

	_empty = _make_label("No tienes comida", COLOR_DIM)
	box.add_child(_empty)

	_close_button = Button.new()
	_close_button.text = "Cerrar"
	_close_button.add_theme_font_override("font", FONT)
	_close_button.add_theme_font_size_override("font_size", 8)
	_close_button.add_theme_color_override("font_color", COLOR_TEXT)
	_close_button.add_theme_color_override("font_focus_color", COLOR_ACCENT)
	_close_button.add_theme_color_override("font_hover_color", COLOR_ACCENT)
	_close_button.pressed.connect(close)
	box.add_child(_close_button)


func _make_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	return label
