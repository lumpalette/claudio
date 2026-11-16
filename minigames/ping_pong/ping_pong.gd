extends Minigame
# Minijuego de ping pong sin rival: devuelve la pelota con la paleta (flechas arriba/abajo).
# NO habla con GameState ni TimeManager: solo emite finished(result) y se borra.

@export var velocidad_paleta := 220.0     # px por segundo
@export var velocidad_pelota := 200.0     # velocidad inicial
@export var velocidad_maxima := 360.0
@export var aumento_por_rebote := 1.05
@export var rebotes_para_ganar := 10
@export var fallos_maximos := 3
@export var y_arriba := 4.0               # borde superior de la cancha
@export var y_abajo := 356.0              # borde inferior
@export var x_derecha := 640.0            # pared de la derecha
@export var x_paleta := 28.0
@export var segundos_mensaje := 1.5

@onready var paleta: Sprite2D = $Paleta
@onready var pelota: Sprite2D = $Pelota
@onready var marcador: Label = $Marcador
@onready var mensaje: Label = $Mensaje

var velocidad := Vector2.ZERO
var rebotes := 0
var fallos := 0
var en_juego := false        # la pelota se está moviendo
var terminado := false
var puede_reiniciar := false # solo en modo prueba (F6)

func _ready() -> void:
	# Sigue funcionando aunque la sala pause el árbol
	process_mode = Node.PROCESS_MODE_ALWAYS
	if es_prueba():
		finished.connect(func(r): print("finished con result = ", r))
	start()

func es_prueba() -> bool:
	# true cuando lo corres solo con F6 (sin sala)
	return get_tree().current_scene == self

func start() -> void:
	rebotes = 0
	fallos = 0
	terminado = false
	puede_reiniciar = false
	mensaje.visible = false
	paleta.position = Vector2(x_paleta, 180)
	actualizar_marcador()
	sacar()

func sacar() -> void:
	# Pone la pelota al centro y la lanza hacia el jugador tras una pausa
	en_juego = false
	pelota.position = Vector2(320, 180)
	await get_tree().create_timer(0.8).timeout
	if terminado:
		return
	velocidad = Vector2(-velocidad_pelota, randf_range(-80.0, 80.0))
	en_juego = true

func _process(delta: float) -> void:
	if terminado:
		return
	# Mover la paleta con flechas (o W y S)
	var dir := 0.0
	if Input.is_action_pressed("move_up"):
		dir -= 1.0
	if Input.is_action_pressed("move_down"):
		dir += 1.0
	var medio_alto := paleta.texture.get_height() / 2.0
	paleta.position.y = clampf(paleta.position.y + dir * velocidad_paleta * delta,
			y_arriba + medio_alto, y_abajo - medio_alto)
	if en_juego:
		mover_pelota(delta)

func mover_pelota(delta: float) -> void:
	var r := pelota.texture.get_width() / 2.0
	var medio_ancho := paleta.texture.get_width() / 2.0
	var medio_alto := paleta.texture.get_height() / 2.0
	pelota.position += velocidad * delta

	# Rebote arriba y abajo
	if pelota.position.y < y_arriba + r:
		pelota.position.y = y_arriba + r
		velocidad.y = absf(velocidad.y)
	elif pelota.position.y > y_abajo - r:
		pelota.position.y = y_abajo - r
		velocidad.y = -absf(velocidad.y)

	# Rebote en la pared derecha (no hay rival)
	if pelota.position.x > x_derecha - r:
		pelota.position.x = x_derecha - r
		velocidad.x = -absf(velocidad.x)

	# Choque con la paleta (solo si la pelota va hacia la izquierda)
	if velocidad.x < 0.0:
		var toca_x := pelota.position.x - r <= paleta.position.x + medio_ancho \
				and pelota.position.x + r >= paleta.position.x - medio_ancho
		var toca_y := absf(pelota.position.y - paleta.position.y) <= medio_alto + r
		if toca_x and toca_y:
			rebote_en_paleta(medio_alto, medio_ancho, r)
			return

	# La pelota se pasó de la paleta: fallo
	if pelota.position.x < -r:
		fallo()

func rebote_en_paleta(medio_alto: float, medio_ancho: float, r: float) -> void:
	rebotes += 1
	pelota.position.x = paleta.position.x + medio_ancho + r
	var rapidez := minf(absf(velocidad.x) * aumento_por_rebote, velocidad_maxima)
	# Según dónde pegue en la paleta, la pelota sube o baja
	var punto := clampf((pelota.position.y - paleta.position.y) / medio_alto, -1.0, 1.0)
	velocidad = Vector2(rapidez, punto * rapidez * 0.8)
	actualizar_marcador()
	if rebotes >= rebotes_para_ganar:
		terminar()

func fallo() -> void:
	fallos += 1
	actualizar_marcador()
	if fallos >= fallos_maximos:
		terminar()
	else:
		sacar()

func actualizar_marcador() -> void:
	marcador.text = "Rebotes: %d/%d     Fallos: %d/%d" % [rebotes, rebotes_para_ganar, fallos, fallos_maximos]

func terminar() -> void:
	terminado = true
	en_juego = false
	var gano := rebotes >= rebotes_para_ganar
	await get_tree().create_timer(segundos_mensaje).timeout
	cerrar(1.0 if gano else 0.5)

func abandonar() -> void:
	terminado = true
	en_juego = false
	cerrar(0.5)

func cerrar(resultado: float) -> void:
	# Avisa el resultado y cierra el minijuego (vuelve a la sala que lo abrió)
	finished.emit(resultado)
	if es_prueba():
		get_tree().quit()  # con F6 no hay sala a la que volver
	else:
		queue_free()
