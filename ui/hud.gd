class_name Hud
extends CanvasLayer
## Interfaz completa del juego: pantalla de título, barras de estado, avisos,
## indicador de interacción, menús de acción, alerta de radiación, pausa y
## pantalla final. La escena principal (main.gd) la controla con las señales.
##
## Las estaciones la buscan con Hud.find(self) para abrir menús.

signal retry_requested
signal title_requested

const FONT := preload("res://shared/fonts/press_start_2p_regular.ttf")
const COLOR_TEXT := Color(0.88, 0.95, 1.0)
const COLOR_ACCENT := Color(0.30, 0.88, 0.95)
const COLOR_DIM := Color(0.55, 0.65, 0.75)
const COLOR_WARN := Color(1.0, 0.56, 0.19)
const COLOR_DANGER := Color(1.0, 0.32, 0.32)
const COLOR_GOOD := Color(0.55, 1.0, 0.45)
const COLOR_PANEL := Color(0.04, 0.08, 0.15, 0.92)

## Estado -> [nombre, ícono, hoja de barra]
const STAT_ROWS := [
	[&"satiety", "Saciedad", "res://ui/stat_bars/comida_40x40.png", "res://ui/stat_bars/hoja_comida.png"],
	[&"hydration", "Hidratación", "res://ui/stat_bars/gota_40x40.png", "res://ui/stat_bars/hoja_agua.png"],
	[&"rest", "Descanso", "res://minigames/assets/luna_bigote_48.png", "res://ui/stat_bars/hoja_animo.png"],
	[&"wellbeing", "Bienestar", "res://ui/stat_bars/corazon_40x40.png", "res://ui/stat_bars/hoja_vida.png"],
	[&"station_oxygen", "Oxígeno", "res://ui/stat_bars/oxigeno_40x40.png", "res://ui/stat_bars/hoja_oxigeno.png"],
	[&"station_water", "Agua", "res://ui/stat_bars/gota_40x40.png", "res://ui/stat_bars/hoja_agua.png"],
	[&"station_energy", "Energía", "res://ui/stat_bars/rayo_sin_cara_40x40.png", "res://ui/stat_bars/hoja_energia.png"],
]
## Filas de las hojas de barras: 11 niveles de 8 px (arriba = lleno).
const BAR_LEVELS := 11
const BAR_SIZE := Vector2(40, 8)

const GAME_OVER_TEXT := {
	"starvation": "Claudio se quedó sin comida.",
	"dehydration": "Claudio se deshidrató.",
	"suffocation": "La estación se quedó sin oxígeno.",
}

const CONTROLS_TEXT := """Flechas / WASD: moverse
E o Enter: interactuar
Esc: pausa / salir de un minijuego

Mantén a Claudio comido, hidratado
y descansado, y a la estación con
oxígeno, agua y energía.

Sobrevive %d días.""" % Balance.TOTAL_DAYS

## Jugador de la sala actual (lo asigna main.gd) para el indicador "[E]".
var player: Player

var _theme: Theme
var _root: Control
var _game_ui: Control
var _stat_bars: Dictionary = {}     # stat -> {bar: TextureRect, value: Label, sheet: Texture2D}
var _room_label: Label
var _prompt_panel: PanelContainer
var _prompt_label: Label
var _toasts: VBoxContainer
var _fade: ColorRect
var _fade_label: Label
var _menu: PanelContainer
var _menu_title: Label
var _menu_info: Label
var _menu_buttons: VBoxContainer
var _menu_on_close: Callable
var _alert: PanelContainer
var _alert_body: Label
var _pause: PanelContainer
var _controls: PanelContainer
var _end: ColorRect
var _end_title: Label
var _end_body: Label
var _end_retry: Button
var _clock: CanvasLayer
var _blink_time := 0.0
var _game_active := false


static func find(node: Node) -> Hud:
	return node.get_tree().get_first_node_in_group(&"hud") as Hud


func _ready() -> void:
	add_to_group(&"hud")
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clock = get_node_or_null(^"HudClock")
	_build_theme()
	_build()

	GameState.stat_changed.connect(_on_stat_changed)
	GameState.message.connect(show_toast)
	GameState.game_over.connect(_on_game_over)
	TimeManager.radiation_started.connect(_on_radiation)
	refresh_stats()
	hide_all()


func _process(delta: float) -> void:
	_blink_time += delta
	var blink_on := fmod(_blink_time, 0.8) < 0.45
	for stat: StringName in _stat_bars:
		var row: Dictionary = _stat_bars[stat]
		var low: bool = GameState.get_stat(stat) < Balance.WARNING_THRESHOLD
		(row["box"] as Control).modulate = COLOR_DANGER if low and blink_on else Color.WHITE
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if _controls.visible:
		_hide_controls()
	elif _menu.visible:
		close_menu()
	elif _pause.visible:
		_resume_from_pause()
	elif _game_active and not get_tree().paused and not _alert.visible and not _fade.visible:
		_open_pause()
	else:
		return
	get_viewport().set_input_as_handled()


# --- API para main.gd ------------------------------------------------------

func show_game(room_name: String) -> void:
	_game_active = true
	_end.hide()
	_hide_overlays()
	_game_ui.show()
	_set_clock_visible(true)
	set_room_name(room_name)
	refresh_stats()


func hide_all() -> void:
	_game_active = false
	_end.hide()
	_hide_overlays()
	_game_ui.hide()
	_set_clock_visible(false)


func set_room_name(room_name: String) -> void:
	_room_label.text = room_name.to_upper()


func refresh_stats() -> void:
	for stat: StringName in _stat_bars:
		_on_stat_changed(stat, GameState.get_stat(stat))


func show_toast(text: String) -> void:
	if not _game_active:
		return
	var panel := _panel(COLOR_PANEL, COLOR_ACCENT)
	var label := _label(text, COLOR_TEXT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	_toasts.add_child(panel)
	while _toasts.get_child_count() > 3:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := panel.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(panel.queue_free)


## Menú de acciones. options: [{text, action: Callable, disabled: bool}].
## La acción elegida se ejecuta después de cerrar el menú y quitar la pausa.
func open_menu(title: String, options: Array[Dictionary], on_close: Callable, info := "") -> void:
	_menu_on_close = on_close
	_menu_title.text = title
	_menu_info.text = info
	_menu_info.visible = info != ""
	for child in _menu_buttons.get_children():
		child.queue_free()
	for option in options:
		var button := _button(option["text"])
		button.disabled = option.get("disabled", false)
		if option.has("action"):
			button.pressed.connect(_choose.bind(option["action"]))
		_menu_buttons.add_child(button)
	var close := _button("Cerrar")
	close.pressed.connect(close_menu)
	_menu_buttons.add_child(close)
	_menu.show()
	get_tree().paused = true
	TimeManager.pause_clock(&"menu")
	await get_tree().process_frame
	_focus_first(_menu_buttons)


func close_menu() -> void:
	_choose(Callable())


## Fundido a negro, dormir y mostrar la hora al despertar.
func play_sleep(on_done: Callable) -> void:
	get_tree().paused = true
	_fade.show()
	_fade.color.a = 0.0
	_fade_label.text = ""
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.6)
	await tw.finished
	var was_night: bool = TimeManager.is_night()
	get_tree().paused = false
	GameState.sleep()
	get_tree().paused = true
	if GameState.is_game_over:
		_fade.hide()
		get_tree().paused = false
		on_done.call()
		return
	_fade_label.text = ("Zzz...\n\n" if was_night else "Siesta...\n\n") + TimeManager.get_clock_text()
	_fade_label.modulate.a = 0.0
	tw = create_tween()
	tw.tween_property(_fade_label, "modulate:a", 1.0, 0.4)
	tw.tween_interval(1.2)
	tw.tween_property(_fade_label, "modulate:a", 0.0, 0.4)
	tw.tween_property(_fade, "color:a", 0.0, 0.6)
	await tw.finished
	_fade.hide()
	# Si llegó una alerta de radiación al despertar, la alerta mantiene la pausa.
	if not _alert.visible:
		get_tree().paused = false
	on_done.call()


# --- Señales del juego ------------------------------------------------------

func _on_stat_changed(stat: StringName, value: float) -> void:
	if not _stat_bars.has(stat):
		return
	var row: Dictionary = _stat_bars[stat]
	var max_value: float = maxf(GameState.stat_max.get(stat, 100.0), 1.0)
	var level := clampi(roundi(value / 100.0 * (BAR_LEVELS - 1)), 0, BAR_LEVELS - 1)
	var atlas: AtlasTexture = (row["bar"] as TextureRect).texture
	atlas.region = Rect2(0, (BAR_LEVELS - 1 - level) * BAR_SIZE.y, BAR_SIZE.x, BAR_SIZE.y)
	var value_label: Label = row["value"]
	value_label.text = "%d" % int(ceilf(value))
	if max_value < 100.0:
		value_label.text += "/%d" % int(max_value)
	value_label.add_theme_color_override(&"font_color", COLOR_DANGER if value < Balance.WARNING_THRESHOLD else COLOR_TEXT)


func _on_radiation(event: Dictionary) -> void:
	_close_menu_silently()
	_alert_body.text = "%s\n\n%s\n\nBienestar -%d y su máximo baja a %d\nel resto de la misión." % [
		event.get("class_text", ""),
		event.get("alert_text", ""),
		int(Balance.RADIATION_PENALTY.get(event.get("class", "M"), 30.0)),
		int(Balance.RADIATION_WELLBEING_MAX),
	]
	_alert.show()
	get_tree().paused = true
	await get_tree().process_frame
	_focus_first(_alert)


func _on_game_over(reason: String) -> void:
	_show_end(false, GAME_OVER_TEXT.get(reason, "La misión fracasó."))


func _show_end(won: bool, text: String) -> void:
	_game_active = false
	_close_menu_silently()
	_alert.hide()
	_pause.hide()
	_end_title.text = "¡MISION CUMPLIDA!" if won else "MISION FALLIDA"
	_end_title.add_theme_color_override(&"font_color", COLOR_GOOD if won else COLOR_DANGER)
	_end_body.text = "%s\n\nResististe hasta el %s" % [text, TimeManager.get_clock_text()]
	_end.show()
	_end.modulate.a = 0.0
	create_tween().tween_property(_end, "modulate:a", 1.0, 0.8)
	get_tree().paused = true
	_end_retry.grab_focus.call_deferred()


# --- Internas ---------------------------------------------------------------

func _choose(action: Callable) -> void:
	if not _menu.visible:
		return
	_menu.hide()
	get_tree().paused = false
	TimeManager.resume_clock(&"menu")
	if action.is_valid():
		action.call()
	var on_close := _menu_on_close
	_menu_on_close = Callable()
	if on_close.is_valid():
		on_close.call()


func _close_menu_silently() -> void:
	if _menu.visible:
		close_menu()


func _close_alert() -> void:
	_alert.hide()
	get_tree().paused = false
	TimeManager.resume_clock(&"alert")


func _show_controls() -> void:
	_controls.show()
	_focus_first(_controls)


func _hide_controls() -> void:
	_controls.hide()
	_focus_first(_pause)


func _open_pause() -> void:
	_pause.show()
	get_tree().paused = true
	_focus_first(_pause)


func _resume_from_pause() -> void:
	_pause.hide()
	_controls.hide()
	get_tree().paused = false


func _pause_then(sig: Signal) -> void:
	_resume_from_pause()
	sig.emit()


func _hide_overlays() -> void:
	_menu.hide()
	_alert.hide()
	_pause.hide()
	_controls.hide()
	_fade.hide()
	_prompt_panel.hide()
	for toast in _toasts.get_children():
		toast.queue_free()


func _update_prompt() -> void:
	var target: Interactable = null
	if _game_active and is_instance_valid(player) and not get_tree().paused \
			and player.state and player.state._current_state and player.state._current_state.name != &"Wait":
		target = player.get_closest_interactable()
	_prompt_panel.visible = target != null
	if target:
		_prompt_label.text = "[E] " + target.get_prompt()


func _set_clock_visible(value: bool) -> void:
	if _clock:
		_clock.visible = value


func _focus_first(container: Node) -> void:
	for child in container.find_children("*", "Button", true, false):
		var button := child as Button
		if button.is_visible_in_tree() and not button.disabled:
			button.grab_focus()
			return


# --- Construcción de la interfaz --------------------------------------------

func _build_theme() -> void:
	var font_file := FONT as FontFile
	if font_file:
		font_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_theme = Theme.new()
	_theme.default_font = FONT
	_theme.default_font_size = 8
	_theme.set_color(&"font_color", &"Label", COLOR_TEXT)
	_theme.set_color(&"font_color", &"Button", COLOR_TEXT)
	_theme.set_color(&"font_hover_color", &"Button", Color.WHITE)
	_theme.set_color(&"font_focus_color", &"Button", Color.WHITE)
	_theme.set_color(&"font_pressed_color", &"Button", COLOR_ACCENT)
	_theme.set_color(&"font_disabled_color", &"Button", COLOR_DIM)
	_theme.set_constant(&"line_spacing", &"Label", 4)
	_theme.set_stylebox(&"normal", &"Button", _box(Color(0.10, 0.18, 0.30), Color(0.20, 0.35, 0.50), 4))
	_theme.set_stylebox(&"hover", &"Button", _box(Color(0.12, 0.30, 0.42), COLOR_ACCENT, 4))
	_theme.set_stylebox(&"focus", &"Button", _box(Color(0.12, 0.30, 0.42, 0.0), COLOR_ACCENT, 4))
	_theme.set_stylebox(&"pressed", &"Button", _box(Color(0.06, 0.20, 0.28), COLOR_ACCENT, 4))
	_theme.set_stylebox(&"disabled", &"Button", _box(Color(0.06, 0.10, 0.16), Color(0.15, 0.22, 0.30), 4))


func _build() -> void:
	_root = Control.new()
	_root.theme = _theme
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_build_game_ui()

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_label = _label("", COLOR_TEXT)
	_fade_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fade.add_child(_fade_label)
	_fade.hide()
	_root.add_child(_fade)

	_build_menu()
	_build_alert()
	_build_pause()
	_build_end()
	_build_controls()


func _build_game_ui() -> void:
	_game_ui = Control.new()
	_game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_game_ui)

	# Barras de estado (arriba a la izquierda)
	var stats_panel := _panel(COLOR_PANEL, Color(0.20, 0.35, 0.50))
	stats_panel.position = Vector2(4, 4)
	_game_ui.add_child(stats_panel)
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override(&"separation", 2)
	stats_panel.add_child(stats)
	for i in STAT_ROWS.size():
		if i == 0:
			stats.add_child(_label("CLAUDIO", COLOR_ACCENT))
		elif i == 4:
			stats.add_child(_label("ESTACION", COLOR_ACCENT))
		stats.add_child(_stat_row(STAT_ROWS[i]))

	# Sala actual (arriba al centro)
	var room_panel := _panel(COLOR_PANEL, Color(0.20, 0.35, 0.50))
	room_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	room_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	room_panel.position.y = 4
	_room_label = _label("", COLOR_ACCENT)
	room_panel.add_child(_room_label)
	_game_ui.add_child(room_panel)

	# Avisos (debajo del nombre de la sala)
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.position.y = 26
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_ui.add_child(_toasts)

	# Indicador de interacción (abajo al centro)
	_prompt_panel = _panel(COLOR_PANEL, COLOR_ACCENT)
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_panel.position.y = -8
	_prompt_label = _label("", Color.WHITE)
	_prompt_panel.add_child(_prompt_label)
	_prompt_panel.hide()
	_game_ui.add_child(_prompt_panel)

	# Ayuda de pausa (abajo a la derecha)
	var hint := _label("ESC: PAUSA", COLOR_DIM)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position += Vector2(-6, -6)
	_game_ui.add_child(hint)


func _stat_row(data: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 3)
	row.tooltip_text = data[1]

	var icon := TextureRect.new()
	icon.texture = load(data[2])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(10, 10)
	row.add_child(icon)

	var name_label := _label(data[1], COLOR_DIM)
	name_label.custom_minimum_size.x = 92
	row.add_child(name_label)

	var atlas := AtlasTexture.new()
	atlas.atlas = load(data[3])
	atlas.region = Rect2(Vector2.ZERO, BAR_SIZE)
	var bar := TextureRect.new()
	bar.texture = atlas
	bar.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	bar.custom_minimum_size = BAR_SIZE
	row.add_child(bar)

	var value := _label("100", COLOR_TEXT)
	value.custom_minimum_size.x = 48
	row.add_child(value)

	_stat_bars[data[0]] = {"bar": bar, "value": value, "box": row}
	return row


func _build_menu() -> void:
	_menu = _centered_panel(COLOR_ACCENT)
	var vbox := _menu.get_child(0) as VBoxContainer
	_menu_title = _label("", COLOR_ACCENT)
	_menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_menu_title)
	_menu_info = _label("", COLOR_DIM)
	_menu_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_menu_info)
	_menu_buttons = VBoxContainer.new()
	_menu_buttons.add_theme_constant_override(&"separation", 3)
	vbox.add_child(_menu_buttons)


func _build_alert() -> void:
	_alert = _centered_panel(COLOR_DANGER)
	var vbox := _alert.get_child(0) as VBoxContainer
	var title := _label("¡ALERTA DE RADIACION!", COLOR_DANGER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_alert_body = _label("", COLOR_TEXT)
	_alert_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_alert_body.custom_minimum_size.x = 380
	vbox.add_child(_alert_body)
	var ok := _button("Entendido")
	ok.pressed.connect(_close_alert)
	vbox.add_child(ok)


func _build_pause() -> void:
	_pause = _centered_panel(COLOR_ACCENT)
	var vbox := _pause.get_child(0) as VBoxContainer
	var title := _label("PAUSA", COLOR_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	for entry: Array in [
		["Continuar", _resume_from_pause],
		["Controles", _show_controls],
		["Reiniciar misión", _pause_then.bind(retry_requested)],
		["Menú principal", _pause_then.bind(title_requested)],
	]:
		var button := _button(entry[0])
		button.pressed.connect(entry[1])
		vbox.add_child(button)


func _build_controls() -> void:
	_controls = _centered_panel(COLOR_ACCENT)
	var vbox := _controls.get_child(0) as VBoxContainer
	var title := _label("CONTROLES", COLOR_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(_label(CONTROLS_TEXT, COLOR_TEXT))
	var back := _button("Volver")
	back.pressed.connect(_hide_controls)
	vbox.add_child(back)


func _build_end() -> void:
	_end = ColorRect.new()
	_end.color = Color(0.02, 0.04, 0.08, 0.94)
	_end.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.hide()
	_root.add_child(_end)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 14)
	center.add_child(vbox)
	_end_title = _label("", COLOR_GOOD)
	_end_title.add_theme_font_size_override(&"font_size", 16)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_title)
	_end_body = _label("", COLOR_TEXT)
	_end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_end_body)
	_end_retry = _button("Reintentar")
	_end_retry.pressed.connect(func() -> void: retry_requested.emit())
	vbox.add_child(_end_retry)
	var menu := _button("Menú principal")
	menu.pressed.connect(func() -> void: title_requested.emit())
	vbox.add_child(menu)


# --- Helpers ----------------------------------------------------------------

func _box(bg: Color, border: Color, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.set_content_margin_all(margin)
	box.content_margin_top = margin + 1
	return box


func _panel(bg: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _box(bg, border, 5))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _centered_panel(border: Color) -> PanelContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _box(Color(0.04, 0.08, 0.15, 0.97), border, 10))
	panel.custom_minimum_size.x = 220
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 8)
	panel.add_child(vbox)
	# El CenterContainer siempre está visible e ignora el ratón; solo se oculta el panel.
	panel.hide()
	return panel


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	return button
