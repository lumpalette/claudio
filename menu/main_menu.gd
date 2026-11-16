extends CanvasLayer
## Menú de inicio "LOBEL · Misión Lunar".
##
## Flujo: Menú → Iniciar → fundido → Cinemática → señal start_game → juego.
## Igual que la cinemática, no cambia de escena por su cuenta: quien lo
## instancie escucha `start_game` y arranca el juego.
##
## Uso desde la escena principal:
##     var menu := preload("res://menu/main_menu.tscn").instantiate()
##     add_child(menu)
##     menu.start_game.connect(_on_start_game)
##
## Controles: ↑/↓ elegir · Enter/Espacio aceptar · también con el mouse.

## Se emite cuando termina la cinemática (o el jugador la salta).
signal start_game(intro_skipped: bool)

## Muestra la cinemática al presionar Iniciar. Si es false, emite start_game directo.
@export var play_cutscene := true
## Al terminar todo, el menú se elimina solo.
@export var free_on_finish := true
@export_file("*.json") var layout_path := "res://menu/data/layout.json"

const CUTSCENE_SCENE := preload("res://cutscene/cutscene.tscn")
const DIM := Color(0.6, 0.6, 0.65)          # botón no seleccionado
const BRIGHT := Color(1.25, 1.25, 1.25)     # pico del pulso del seleccionado
const STAR_COLOR := Color(0.85, 0.95, 1.0)

@onready var _stage: Control = %Stage
@onready var _background: TextureRect = %Background
@onready var _stars: Control = %Stars
@onready var _logo: TextureRect = %Logo
@onready var _astronaut: TextureRect = %Astronaut
@onready var _start_button: TextureButton = %StartButton
@onready var _exit_button: TextureButton = %ExitButton
@onready var _fade: ColorRect = %Fade

var _buttons: Array[TextureButton] = []
var _selected := 0
var _active := false
var _pulse_tween: Tween
var _layout: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_buttons = [_start_button, _exit_button]
	_load_layout()
	for i in _buttons.size():
		var button := _buttons[i]
		button.focus_mode = Control.FOCUS_NONE   # el teclado se maneja en _unhandled_input
		button.pivot_offset = button.size / 2.0
		button.mouse_entered.connect(_select.bind(i))
		button.pressed.connect(_activate.bind(i))
	_start_idle_animations()
	_select(0)
	# Entrada desde negro.
	_fade.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.6)
	tw.tween_callback(func(): _active = true)


# ---------------------------------------------------------------- entrada

func _unhandled_input(event: InputEvent) -> void:
	if not _active or event.is_echo():
		return
	if event.is_action_pressed("ui_down"):
		_select((_selected + 1) % _buttons.size())
	elif event.is_action_pressed("ui_up"):
		_select((_selected - 1 + _buttons.size()) % _buttons.size())
	elif event.is_action_pressed("ui_accept"):
		_activate(_selected)
	else:
		return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- layout

func _load_layout() -> void:
	var file := FileAccess.open(layout_path, FileAccess.READ)
	if file == null:
		push_warning("MainMenu: no se encontró %s, se usan las posiciones de la escena." % layout_path)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("MainMenu: %s no es un JSON válido." % layout_path)
		return
	_layout = parsed
	_background.texture = load(_layout.get("background", ""))
	var nodes := {
		"logo": _logo,
		"start_button": _start_button,
		"exit_button": _exit_button,
		"astronaut": _astronaut,
	}
	for layer in _layout.get("layers", []):
		var node: Control = nodes.get(layer.get("id", ""))
		if node == null:
			continue
		var texture: Texture2D = load(layer.file)
		if node is TextureButton:
			(node as TextureButton).texture_normal = texture
		elif node is TextureRect:
			(node as TextureRect).texture = texture
		node.position = Vector2(layer.x, layer.y)
		node.size = Vector2(layer.w, layer.h)


# ---------------------------------------------------------------- botones

## Selección simulada (opción A): el elegido palpita y crece un poco,
## los demás se oscurecen.
func _select(index: int) -> void:
	_selected = index
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	for i in _buttons.size():
		var button := _buttons[i]
		var is_selected := i == index
		var tw := create_tween().set_parallel()
		tw.tween_property(button, "scale", Vector2.ONE * (1.04 if is_selected else 1.0), 0.12)
		tw.tween_property(button, "self_modulate", Color.WHITE if is_selected else DIM, 0.12)
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_interval(0.12)
	_pulse_tween.tween_property(_buttons[index], "self_modulate", BRIGHT, 0.6).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_property(_buttons[index], "self_modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)


func _activate(index: int) -> void:
	if not _active:
		return
	_select(index)
	_active = false
	var button := _buttons[index]
	# Efecto de "presionado": se hunde 1 px y regresa.
	var base_y := button.position.y
	var press := create_tween()
	press.tween_property(button, "position:y", base_y + 1, 0.05)
	press.tween_property(button, "position:y", base_y, 0.08)
	if button == _start_button:
		press.tween_callback(_on_start)
	elif button == _exit_button:
		press.tween_callback(_on_exit)


func _on_start() -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.5)
	tw.tween_callback(_launch_cutscene)


func _launch_cutscene() -> void:
	_stop_animations()
	_stage.visible = false
	if not play_cutscene:
		_emit_start(false)
		if free_on_finish:
			queue_free()
		return
	var cutscene := CUTSCENE_SCENE.instantiate()
	# Se agrega como hermano: si el menú se borra, la cinemática sigue viva.
	get_parent().add_child.call_deferred(cutscene)
	cutscene.finished.connect(_emit_start)
	if free_on_finish:
		cutscene.tree_exited.connect(queue_free)


func _emit_start(skipped: bool) -> void:
	start_game.emit(skipped)
	if start_game.get_connections().is_empty():
		print("MainMenu: start_game (intro_skipped=%s). Conecta esta señal en la escena principal." % skipped)


func _on_exit() -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.4)
	tw.tween_callback(get_tree().quit)


# ---------------------------------------------------------------- animaciones

func _start_idle_animations() -> void:
	# Logo flotando.
	var logo_y := _logo.position.y
	var float_tw := create_tween().set_loops()
	float_tw.tween_property(_logo, "position:y", logo_y - 2, 1.4).set_trans(Tween.TRANS_SINE)
	float_tw.tween_property(_logo, "position:y", logo_y, 1.4).set_trans(Tween.TRANS_SINE)
	# Astronauta "respirando" (crece desde los pies).
	_astronaut.pivot_offset = Vector2(_astronaut.size.x / 2.0, _astronaut.size.y)
	var breathe := create_tween().set_loops()
	breathe.tween_property(_astronaut, "scale:y", 1.03, 0.9).set_trans(Tween.TRANS_SINE)
	breathe.tween_property(_astronaut, "scale:y", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	_spawn_stars()


func _spawn_stars() -> void:
	var data: Dictionary = _layout.get("stars", {})
	var count := int(data.get("count", 14))
	var area: Array = data.get("area", [280, 8, 630, 92])
	var avoid: Array = data.get("avoid", [])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7   # mismas posiciones siempre
	var placed := 0
	var attempts := 0
	while placed < count and attempts < 500:
		attempts += 1
		var pos := Vector2(rng.randi_range(int(area[0]), int(area[2])), rng.randi_range(int(area[1]), int(area[3])))
		var blocked := false
		for zone in avoid:
			if pos.distance_to(Vector2(zone.x, zone.y)) < zone.radius:
				blocked = true
				break
		if blocked:
			continue
		var star := ColorRect.new()
		star.color = STAR_COLOR
		star.size = Vector2.ONE * (2 if rng.randf() < 0.3 else 1)
		star.position = pos
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.modulate.a = 0.0
		_stars.add_child(star)
		var tw := star.create_tween().set_loops()
		tw.tween_interval(rng.randf_range(0.0, 3.0))
		tw.tween_property(star, "modulate:a", 1.0, rng.randf_range(0.4, 0.9))
		tw.tween_property(star, "modulate:a", 0.0, rng.randf_range(0.6, 1.2))
		placed += 1


func _stop_animations() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	for star in _stars.get_children():
		star.queue_free()
