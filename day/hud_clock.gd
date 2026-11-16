extends CanvasLayer
## Reloj del HUD (parte inferior de la pantalla).
##
## La luna funciona como manecilla: empieza abajo a la izquierda a las 06:00
## y avanza hasta abajo a la derecha a las 22:00 (Balance.BEDTIME_HOUR).
## Pasada esa hora, si Claudio sigue despierto, la luna se queda al final
## y la luna y la hora parpadean hasta que se vaya a dormir.
##
## Solo escucha a TimeManager: no cambia estados del juego.

## Hora de inicio y fin del arco.
@export var start_hour := Balance.SLEEP_UNTIL_HOUR
@export var end_hour := Balance.BEDTIME_HOUR
## TimeManager arranca con el reloj pausado (motivo &"init").
## Si es true, este HUD lo reanuda al aparecer para que el tiempo empiece a correr.
@export var start_clock_on_ready := true
## Velocidad (grados/segundo) con la que la manecilla alcanza su posición
## después de un salto de tiempo (comer, dormir, minijuegos).
@export var hand_speed := 240.0
@export var day_format := "DÍA %d"

const FONT := preload("res://cutscene/fonts/press_start_2p_regular.ttf")
const COLOR_ACCENT := Color(0.30, 0.88, 0.95)
const COLOR_TEXT := Color(0.88, 0.95, 1.0)
const COLOR_LATE := Color(1.0, 0.56, 0.19)   # naranja: ya es hora de dormir
## Ángulo de la manecilla en los extremos (0° = apuntando hacia arriba).
const HAND_MIN_DEG := -80.0
const HAND_MAX_DEG := 80.0

@onready var _hand: TextureRect = %Hand
@onready var _day_label: Label = %DayLabel
@onready var _time_label: Label = %TimeLabel
@onready var _start_label: Label = %StartLabel
@onready var _end_label: Label = %EndLabel

var _target_deg := HAND_MIN_DEG
var _sleep_tween: Tween
var _blink_tween: Tween
var _blinking := false
var _last_minute := -1
var _last_day := -1


func _ready() -> void:
	var font_file := FONT as FontFile
	if font_file:
		font_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_style(_day_label, COLOR_ACCENT)
	_style(_time_label, COLOR_TEXT)
	_style(_start_label, COLOR_ACCENT)
	_style(_end_label, COLOR_ACCENT)
	_start_label.text = _format_hour(start_hour)
	_end_label.text = _format_hour(end_hour)

	TimeManager.time_changed.connect(_on_time_changed)
	TimeManager.sleep_started.connect(_on_sleep_started)
	TimeManager.sleep_ended.connect(_on_sleep_ended)
	_on_time_changed(TimeManager.get_day(), TimeManager.get_hour())
	_hand.rotation_degrees = _target_deg   # sin animación la primera vez

	if start_clock_on_ready:
		TimeManager.resume_clock(&"init")


func _process(delta: float) -> void:
	_hand.rotation_degrees = move_toward(_hand.rotation_degrees, _target_deg, hand_speed * delta)


func _on_time_changed(day: int, hour: float) -> void:
	# Manecilla
	var t := clampf((hour - start_hour) / (end_hour - start_hour), 0.0, 1.0)
	var is_night := hour < start_hour or hour > end_hour
	if is_night:
		t = 1.0
	_target_deg = lerpf(HAND_MIN_DEG, HAND_MAX_DEG, t)
	_set_blinking(TimeManager.is_past_bedtime() and not TimeManager.is_sleeping)

	# Textos (solo cuando cambian, no cada cuadro)
	var minute := int(hour * 60.0)
	if minute != _last_minute:
		_last_minute = minute
		_time_label.text = "%02d:%02d" % [minute / 60, minute % 60]
	if day != _last_day:
		_last_day = day
		_day_label.text = day_format % day


## Parpadeo de "ya es hora de dormir": luna y hora titilan, la hora en naranja.
func _set_blinking(value: bool) -> void:
	if value == _blinking:
		return
	_blinking = value
	if _blink_tween and _blink_tween.is_valid():
		_blink_tween.kill()
	if value:
		_time_label.add_theme_color_override("font_color", COLOR_LATE)
		_blink_tween = create_tween().set_loops()
		_blink_tween.tween_property(_hand, "modulate:a", 0.2, 0.35)
		_blink_tween.parallel().tween_property(_time_label, "modulate:a", 0.3, 0.35)
		_blink_tween.tween_property(_hand, "modulate:a", 1.0, 0.35)
		_blink_tween.parallel().tween_property(_time_label, "modulate:a", 1.0, 0.35)
	else:
		_time_label.add_theme_color_override("font_color", COLOR_TEXT)
		_hand.modulate.a = 1.0
		_time_label.modulate.a = 1.0


## Dormir en TimeManager es instantáneo (sleep_started y sleep_ended llegan en el
## mismo cuadro), así que la luna se atenúa de golpe y se recupera poco a poco
## mientras regresa a las 06:00.
func _on_sleep_started() -> void:
	if _sleep_tween and _sleep_tween.is_valid():
		_sleep_tween.kill()
	_hand.self_modulate.a = 0.3


func _on_sleep_ended() -> void:
	if _sleep_tween and _sleep_tween.is_valid():
		_sleep_tween.kill()
	_sleep_tween = create_tween()
	_sleep_tween.tween_interval(0.6)
	_sleep_tween.tween_property(_hand, "self_modulate:a", 1.0, 0.8)


func _format_hour(hour: float) -> String:
	return "%02d:%02d" % [int(hour), int(fmod(hour, 1.0) * 60.0)]


func _style(label: Label, color: Color) -> void:
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
