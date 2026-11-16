extends CanvasLayer
## Pantalla negra del desmayo: "Claudio tuvo que irse a dormir".
##
## Escucha TimeManager.fainted. El salto de tiempo del desmayo es instantáneo
## (TimeManager duerme hasta las 06:00 en el mismo cuadro), así que esta
## pantalla lo tapa: aparece en negro de inmediato, muestra el mensaje,
## lo desvanece y revela la mañana siguiente.
## Mientras se ve, el reloj está pausado (motivo &"faint_screen").

@export var message := "Claudio tuvo que irse a dormir"
@export var hold_seconds := 2.2

const FONT := preload("res://cutscene/fonts/press_start_2p_regular.ttf")

@onready var _root: Control = %Root
@onready var _black: ColorRect = %Black
@onready var _label: Label = %Message

var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var font_file := FONT as FontFile
	if font_file:
		font_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0))
	_label.uppercase = true
	_root.visible = false
	TimeManager.fainted.connect(_on_fainted)


func _on_fainted() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	TimeManager.pause_clock(&"faint_screen")
	_label.text = message
	_root.visible = true
	_black.color.a = 1.0            # negro inmediato, antes de que se vea el salto
	_label.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", 1.0, 0.6)
	_tween.tween_interval(hold_seconds)
	_tween.tween_property(_label, "modulate:a", 0.0, 0.6)
	_tween.tween_interval(0.3)
	_tween.tween_property(_black, "color:a", 0.0, 0.9)
	_tween.tween_callback(_finish)


func _finish() -> void:
	_root.visible = false
	TimeManager.resume_clock(&"faint_screen")
