class_name Bolita
extends Area2D
# Una bolita que cae. Puede ser "O" (oxígeno) o "H" (hidrógeno).

signal llego_al_suelo

@export var tipo := "O"
@export var velocidad := 50.0   # px por segundo
@export var y_suelo := 344.0

const TEXTURA_O := preload("assets/bola_O.png")
const TEXTURA_H := preload("assets/bola_H.png")

var activa := true  # false cuando ya fue atrapada o llegó al suelo

func _ready() -> void:
	$Sprite2D.texture = TEXTURA_O if tipo == "O" else TEXTURA_H

func _process(delta: float) -> void:
	if not activa:
		return
	position.y += velocidad * delta
	if position.y >= y_suelo:
		activa = false
		llego_al_suelo.emit()  # sin penalización
		queue_free()

func atrapar() -> void:
	activa = false
	queue_free()
