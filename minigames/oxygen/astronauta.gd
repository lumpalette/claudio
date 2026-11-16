class_name Astronauta
extends Area2D
# El astronauta se mueve a los lados y atrapa bolitas con el tanque.

signal bolita_atrapada(tipo: String)

@export var velocidad := 160.0
@export var x_min := 20.0
@export var x_max := 620.0

@onready var sprite: Sprite2D = $Sprite2D

var activo := false        # solo se mueve mientras el juego corre
var reaccionando := false  # true durante los 0.4 s de acierto/error
var tiempo_anim := 0.0

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:
	if not activo:
		return

	# Teclas directas para no tocar el Input Map del proyecto
	var dir := 0.0
	if Input.is_action_pressed("move_left"):
		dir -= 1.0
	if Input.is_action_pressed("move_right"):
		dir += 1.0

	# Mover y no salirse de la pantalla
	position.x = clampf(position.x + dir * velocidad * delta, x_min, x_max)

	if dir != 0.0:
		sprite.flip_h = dir < 0.0

	# Animación (no se cambia mientras muestra acierto o error)
	if not reaccionando:
		if dir != 0.0:
			tiempo_anim += delta
			sprite.frame = 1 + int(tiempo_anim / 0.15) % 2  # alterna cuadros 1 y 2
		else:
			tiempo_anim = 0.0
			sprite.frame = 0  # idle

func _on_area_entered(area: Area2D) -> void:
	var bolita := area as Bolita
	if bolita == null or not bolita.activa:
		return
	var tipo := bolita.tipo
	bolita.atrapar()
	reaccionar(tipo == "O")
	bolita_atrapada.emit(tipo)

func reaccionar(acierto: bool) -> void:
	# El tanque se pone verde (acierto) o rojo (error) por 0.4 s
	reaccionando = true
	sprite.frame = 3 if acierto else 4
	await get_tree().create_timer(0.4).timeout
	reaccionando = false
