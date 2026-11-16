extends CanvasLayer
## Cinemática de Claudio. La misma escena sirve para la introducción
## (data/story.json, 5 escenas) y para el final de victoria
## (data/ending.json, 4 escenas; ver cutscene/ending.tscn).
##
## Es una pieza autónoma: no cambia de escena ni toca GameState.
## Cuando termina (Jugar o Saltar) emite `finished(skipped)` y quien la
## instancie decide qué hacer después.
##
## Uso desde la escena principal:
##     var intro := preload("res://cutscene/cutscene.tscn").instantiate()
##     add_child(intro)
##     intro.finished.connect(_on_intro_finished)
##
## Final de victoria (lo arma quien tenga la escena principal):
##     GameState.victory.connect(_on_victory)
##
##     func _on_victory() -> void:
##         get_tree().paused = true   # la cinemática sigue (PROCESS_MODE_ALWAYS)
##         var ending := preload("res://cutscene/ending.tscn").instantiate()
##         add_child(ending)
##         ending.finished.connect(_on_ending_finished)
##
##     ## "SALIR" (o Saltar) regresa al menú principal con una partida nueva.
##     func _on_ending_finished(_skipped: bool) -> void:
##         get_tree().paused = false
##         GameState.new_game()
##         get_tree().change_scene_to_file("res://<escena que muestra el menú>.tscn")
##
## Controles: Enter/Espacio/→ siguiente · ← anterior · Esc saltar.
## Si el texto se está escribiendo, el primer "siguiente" lo completa.

signal finished(skipped: bool)

## Empieza sola al entrar al árbol. Desactívalo si prefieres llamar a play().
@export var autoplay := true
## Al terminar: fundido de salida y queue_free(). Si es false, se queda en negro.
@export var free_on_finish := true
## Usar los fondos de alta resolución (originals/) para que el zoom se vea suave.
@export var use_hd_backgrounds := true
@export_file("*.json") var story_path := "res://cutscene/data/story.json"

const FONT := preload("res://shared/fonts/press_start_2p_regular.ttf")
const COLOR_TEXT := Color(0.88, 0.95, 1.0)
const COLOR_ACCENT := Color(0.30, 0.88, 0.95)
const COLOR_DOT_OFF := Color(0.30, 0.88, 0.95, 0.25)

@onready var _world: Control = %World
@onready var _background: TextureRect = %Background
@onready var _effects: Control = %Effects
@onready var _character: TextureRect = %Character
@onready var _flash: ColorRect = %Flash
@onready var _title_box: PanelContainer = %TitleBox
@onready var _title_number: Label = %TitleNumber
@onready var _title: Label = %Title
@onready var _speaker: Label = %Speaker
@onready var _dialog_text: Label = %DialogText
@onready var _progress: Label = %Progress
@onready var _progress_dots: HBoxContainer = %ProgressDots
@onready var _skip_button: TextureButton = %SkipButton
@onready var _back_button: TextureButton = %BackButton
@onready var _next_button: TextureButton = %NextButton
@onready var _fade: ColorRect = %Fade

var _story: Dictionary = {}
var _scenes: Array = []
var _textures: Dictionary = {}       # ruta -> Texture2D (precargadas)
var _index := 0
var _active := false                 # acepta entrada
var _busy := false                   # en transición
var _typing_tween: Tween
var _scene_tweens: Array[Tween] = []
var _title_base_x := 0.0


func _ready() -> void:
	# Sigue funcionando aunque la escena principal pause el juego durante la intro.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Fuente pixel nítida, sin suavizado.
	var font_file := FONT as FontFile
	if font_file:
		font_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font_file.hinting = TextServer.HINTING_NONE
	_load_story()
	_style_ui()
	_title_base_x = _title_box.position.x
	_skip_button.pressed.connect(skip)
	_back_button.pressed.connect(back)
	_next_button.pressed.connect(next)
	_fade.color.a = 1.0
	if autoplay:
		play()


# ---------------------------------------------------------------- API pública

func play() -> void:
	_index = 0
	_show_scene(_index)
	_active = true
	_busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.8)
	tw.tween_callback(func(): _busy = false)


func next() -> void:
	if not _active or _busy:
		return
	if _is_typing():
		_finish_typing()
		return
	if _index >= _scenes.size() - 1:
		_finish(false)
	else:
		_go_to(_index + 1)


func back() -> void:
	if not _active or _busy or _index == 0:
		return
	_go_to(_index - 1)


func skip() -> void:
	if not _active or _busy:
		return
	_finish(true)


# ---------------------------------------------------------------- entrada

func _unhandled_input(event: InputEvent) -> void:
	if not _active or event.is_echo():
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_right"):
		next()
	elif event.is_action_pressed("ui_left"):
		back()
	elif event.is_action_pressed("ui_cancel"):
		skip()
	else:
		return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- datos

func _load_story() -> void:
	var file := FileAccess.open(story_path, FileAccess.READ)
	if file == null:
		push_error("Cutscene: no se pudo abrir %s" % story_path)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Cutscene: %s no es un JSON válido" % story_path)
		return
	_story = parsed
	_scenes = _story.get("scenes", [])
	# Precarga todas las texturas para que no haya tirones al cambiar de escena.
	for scene in _scenes:
		_texture(scene.get("background", ""))
		_texture(scene.get("background_hd", ""))
		if scene.get("character") != null:
			_texture("res://cutscene/assets/characters/claudio_ai.png")
	for id in _story.get("buttons", {}):
		for state in _story.buttons[id]:
			_texture(_story.buttons[id][state])


func _texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]


# ---------------------------------------------------------------- estilo

func _style_ui() -> void:
	_set_label(_title_number, 8, COLOR_ACCENT)
	_set_label(_title, 12, COLOR_TEXT)
	_set_label(_speaker, 8, COLOR_ACCENT)
	_set_label(_dialog_text, 12, COLOR_TEXT)
	_dialog_text.add_theme_constant_override("line_spacing", 8)
	_set_label(_progress, 8, COLOR_ACCENT)
	for button in [_skip_button, _back_button, _next_button]:
		button.focus_mode = Control.FOCUS_NONE   # el teclado se maneja en _unhandled_input


func _set_label(label: Label, size: int, color: Color) -> void:
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.uppercase = true


# ---------------------------------------------------------------- escenas

func _go_to(index: int) -> void:
	_busy = true
	var half: float = _story.get("transition_ms", 280) / 2000.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, half)
	tw.tween_callback(_show_scene.bind(index))
	tw.tween_property(_fade, "color:a", 0.0, half)
	tw.tween_callback(func(): _busy = false)


func _show_scene(index: int) -> void:
	_index = index
	_clear_scene()
	var scene: Dictionary = _scenes[index]
	var effects: Dictionary = scene.get("effects", {})

	# Fondo
	var bg_path: String = scene.get("background", "")
	if use_hd_backgrounds and scene.has("background_hd"):
		bg_path = scene.background_hd
		_background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background.texture = _texture(bg_path)

	# Textos
	_title_number.text = scene.get("number", "%02d" % (index + 1))
	_title.text = scene.get("title", "")
	_title_box.reset_size()   # se ajusta al largo del título
	_speaker.text = scene.get("speaker", "")
	_dialog_text.text = "\n".join(scene.get("lines", []))
	_dialog_text.visible_characters = 0
	_progress.text = "%d / %d" % [index + 1, _scenes.size()]
	_update_dots(index)

	# Botones
	for b in scene.get("buttons", []):
		_setup_button(b)

	# Personaje y efectos
	_setup_character(scene.get("character"))
	_play_camera(effects.get("camera", {}))
	_play_title(effects.get("title_delay", 0.2))
	_start_typing(effects.get("text_delay", 0.5))
	if effects.has("shake"):
		_play_shake(effects.shake)
	if effects.has("flash"):
		_play_flash(effects.flash)
	if effects.has("sparks"):
		_play_sparks(effects.sparks)
	if effects.has("signal_waves"):
		_play_signal_waves(effects.signal_waves)
	if effects.has("glow"):
		_play_glow(effects.glow)
	if effects.get("pulse_play", false):
		_play_pulse(_next_button)
	if effects.has("banner"):
		_play_banner(effects.banner)


func _clear_scene() -> void:
	for tw in _scene_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_scene_tweens.clear()
	if _typing_tween and _typing_tween.is_valid():
		_typing_tween.kill()
	for child in _effects.get_children():
		child.queue_free()
	_world.scale = Vector2.ONE
	_world.position = Vector2.ZERO
	_world.pivot_offset = Vector2.ZERO
	_flash.color.a = 0.0
	_character.visible = false
	_character.modulate.a = 1.0
	_character.scale = Vector2.ONE
	_next_button.self_modulate = Color.WHITE
	_title_box.modulate.a = 1.0
	_title_box.position.x = _title_base_x


func _tw() -> Tween:
	var tw := create_tween()
	_scene_tweens.append(tw)
	return tw


func _update_dots(index: int) -> void:
	for child in _progress_dots.get_children():
		child.queue_free()
	for i in _scenes.size():
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(6, 3)
		dot.color = COLOR_ACCENT if i == index else COLOR_DOT_OFF
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_progress_dots.add_child(dot)


func _setup_button(data: Dictionary) -> void:
	var id: String = data.get("id", "")
	var button: TextureButton
	match id:
		"skip": button = _skip_button
		"back": button = _back_button
		"next", "play", "exit": button = _next_button
		_: return
	var tex: Dictionary = _story.buttons[id]
	var state: String = data.get("state", "normal")
	# "hover" como estado inicial = botón resaltado por defecto (el que activa Enter).
	button.texture_normal = _texture(tex.hover if state == "hover" else tex.normal)
	button.texture_hover = _texture(tex.hover)
	button.texture_pressed = _texture(tex.pressed)
	button.texture_disabled = _texture(tex.disabled)
	button.disabled = state == "disabled"
	button.position = Vector2(data.get("x", 0), data.get("y", 0))


# ---------------------------------------------------------------- texto

func _start_typing(delay: float) -> void:
	var total := _dialog_text.get_total_character_count()
	var speed: float = _story.get("type_speed", 40)
	_typing_tween = create_tween()
	_typing_tween.tween_interval(delay)
	_typing_tween.tween_property(_dialog_text, "visible_characters", total, total / speed)


func _is_typing() -> bool:
	return _typing_tween != null and _typing_tween.is_running()


func _finish_typing() -> void:
	if _typing_tween:
		_typing_tween.kill()
	_dialog_text.visible_characters = -1


func _play_title(delay: float) -> void:
	_title_box.modulate.a = 0.0
	_title_box.position.x = _title_base_x - 16
	var tw := _tw().set_parallel()
	tw.tween_property(_title_box, "modulate:a", 1.0, 0.4).set_delay(delay)
	tw.tween_property(_title_box, "position:x", _title_base_x, 0.4).set_delay(delay) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- personaje

func _setup_character(data) -> void:
	if data == null:
		return
	_character.texture = _texture("res://cutscene/assets/characters/claudio_ai.png")
	var target := Vector2(data.get("x", 0), data.get("y", 0))
	_character.position = target
	_character.pivot_offset = Vector2(_character.size.x / 2.0, _character.size.y)
	_character.visible = true
	var delay: float = data.get("delay", 0.0)
	match data.get("anim", ""):
		"fade_in":
			_character.modulate.a = 0.0
			_tw().tween_property(_character, "modulate:a", 1.0, 0.5).set_delay(delay)
		"breathe":
			var tw := _tw().set_loops()
			tw.tween_property(_character, "scale:y", 1.03, 0.9).set_trans(Tween.TRANS_SINE)
			tw.tween_property(_character, "scale:y", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
		"walk_in":
			var duration: float = data.get("duration", 1.5)
			_character.position.x = data.get("from_x", target.x - 80)
			var walk := _tw()
			walk.tween_interval(delay)
			walk.tween_property(_character, "position:x", target.x, duration)
			# Rebote de pasos mientras camina; se detiene al llegar.
			var steps := int(duration / 0.3)
			var bob := _tw()
			bob.tween_interval(delay)
			for i in steps:
				bob.tween_property(_character, "position:y", target.y - 2, 0.15)
				bob.tween_property(_character, "position:y", target.y, 0.15)


# ---------------------------------------------------------------- efectos

## Zoom lento que termina exactamente en el encuadre original (escala 1).
func _play_camera(data: Dictionary) -> void:
	if data.is_empty():
		return
	var focus: Array = data.get("focus", [320, 180])
	_world.pivot_offset = Vector2(focus[0], focus[1])
	var from: float = data.get("zoom_from", 1.08)
	_world.scale = Vector2(from, from)
	_tw().tween_property(_world, "scale", Vector2.ONE, data.get("duration", 3.0)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _play_shake(data: Dictionary) -> void:
	var strength: float = data.get("strength", 4)
	var duration: float = data.get("duration", 0.5)
	var tw := _tw()
	tw.tween_interval(data.get("delay", 0.0))
	var steps := int(duration / 0.04)
	for i in steps:
		var falloff := 1.0 - float(i) / steps
		var offset := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * falloff
		tw.tween_property(_world, "position", offset.round(), 0.04)
	tw.tween_property(_world, "position", Vector2.ZERO, 0.04)


func _play_flash(data: Dictionary) -> void:
	var color := Color(data.get("color", "#ff3020"))
	color.a = 0.0
	_flash.color = color
	var alpha: float = data.get("alpha", 0.45)
	var tw := _tw()
	tw.tween_interval(data.get("delay", 0.0))
	for i in int(data.get("count", 2)):
		tw.tween_property(_flash, "color:a", alpha, 0.08)
		tw.tween_property(_flash, "color:a", 0.0, 0.25)


func _play_sparks(data: Dictionary) -> void:
	var sparks := CPUParticles2D.new()
	sparks.position = Vector2(data.get("x", 0), data.get("y", 0))
	sparks.one_shot = true
	sparks.emitting = false
	sparks.amount = 14
	sparks.lifetime = 0.6
	sparks.explosiveness = 0.9
	sparks.direction = Vector2(0, -1)
	sparks.spread = 70.0
	sparks.gravity = Vector2(0, 160)
	sparks.initial_velocity_min = 30.0
	sparks.initial_velocity_max = 70.0
	sparks.scale_amount_min = 1.0
	sparks.scale_amount_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.6))
	ramp.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
	sparks.color_ramp = ramp
	_effects.add_child(sparks)
	var tw := _tw().set_loops()
	tw.tween_callback(sparks.restart)
	tw.tween_interval(data.get("interval", 1.0) * randf_range(0.7, 1.3))


func _play_signal_waves(data: Dictionary) -> void:
	var origin := Vector2(data.get("x", 0), data.get("y", 0))
	var tw := _tw().set_loops()
	tw.tween_callback(_spawn_wave.bind(origin))
	tw.tween_interval(data.get("interval", 0.7))


func _spawn_wave(origin: Vector2) -> void:
	var wave := Node2D.new()
	wave.position = origin
	wave.set_meta("radius", 2.0)
	# Arco apuntando hacia la Tierra (arriba a la izquierda).
	var on_draw := func() -> void:
		var r: float = wave.get_meta("radius")
		wave.draw_arc(Vector2.ZERO, r, deg_to_rad(-200), deg_to_rad(-110), 16, COLOR_ACCENT, 1.0)
	wave.draw.connect(on_draw)
	var set_radius := func(r: float) -> void:
		wave.set_meta("radius", r)
		wave.queue_redraw()
	_effects.add_child(wave)
	# Tween ligado a la onda: muere con ella.
	var tw := wave.create_tween().set_parallel()
	tw.tween_method(set_radius, 2.0, 34.0, 1.4)
	tw.tween_property(wave, "modulate:a", 0.0, 1.4).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(wave.queue_free)


func _play_glow(data: Dictionary) -> void:
	var radius: float = data.get("radius", 60)
	var color := Color(data.get("color", "#4de2f1"))
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color, 0.7))
	gradient.set_color(1, Color(color, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = int(radius * 2)
	texture.height = int(radius * 2)
	var glow := Sprite2D.new()
	glow.texture = texture
	glow.position = Vector2(data.get("x", 0), data.get("y", 0))
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = material
	glow.modulate.a = 0.25
	_effects.add_child(glow)
	var tw := _tw().set_loops()
	tw.tween_property(glow, "modulate:a", 0.6, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(glow, "modulate:a", 0.25, 1.1).set_trans(Tween.TRANS_SINE)


## Letrero grande (ej. "¡CONTINUARÁ...!"): aparece con un salto y luego late.
## data: text, x, y (centro), size (múltiplo de 8 para la fuente pixel), color, outline, delay.
func _play_banner(data: Dictionary) -> void:
	var label := Label.new()
	label.text = data.get("text", "")
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", int(data.get("size", 32)))
	label.add_theme_color_override("font_color", Color(data.get("color", "#ffcc33")))
	label.add_theme_color_override("font_outline_color", Color(data.get("outline", "#3a1c00")))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effects.add_child(label)
	label.reset_size()
	label.pivot_offset = label.size / 2.0
	label.position = Vector2(data.get("x", 320), data.get("y", 150)) - label.size / 2.0
	label.scale = Vector2(0.3, 0.3)
	label.modulate.a = 0.0

	var tw := _tw()
	tw.tween_interval(data.get("delay", 0.5))
	tw.tween_property(label, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(label, "scale", Vector2(1.15, 1.15), 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "scale", Vector2.ONE, 0.15)
	tw.tween_callback(_beat_banner.bind(label))


func _beat_banner(label: Label) -> void:
	var beat := _tw().set_loops()
	beat.tween_property(label, "scale", Vector2(1.05, 1.05), 0.5).set_trans(Tween.TRANS_SINE)
	beat.tween_property(label, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)


func _play_pulse(button: TextureButton) -> void:
	var tw := _tw().set_loops()
	tw.tween_property(button, "self_modulate", Color(1.4, 1.4, 1.4), 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(button, "self_modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------- final

func _finish(skipped: bool) -> void:
	_active = false
	_busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.4)
	tw.tween_callback(_emit_finished.bind(skipped))
	if free_on_finish:
		tw.tween_interval(0.05)
		tw.tween_property(_fade, "color:a", 0.0, 0.4)
		tw.tween_callback(queue_free)


func _emit_finished(skipped: bool) -> void:
	_clear_scene()
	finished.emit(skipped)
	if finished.get_connections().is_empty():
		print("Cutscene terminada (skipped=%s). Conecta la señal 'finished' en la escena principal." % skipped)
