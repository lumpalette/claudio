extends Minigame
# Control principal del minijuego de oxígeno.
# NO habla con GameState ni TimeManager: solo emite finished(result)
# y se borra. La sala que lo abre aplica el efecto.


@export var escena_bolita: PackedScene
@export var total_bolitas := 10
@export var num_oxigeno := 6          # el resto son H
@export var aciertos_para_ganar := 5  # solo para el mensaje de pantalla
@export var velocidad_caida := 50.0
@export var separacion := 1.5         # segundos entre bolitas
@export var segundos_mensaje := 0.6   # cuánto se ve el mensaje final

@onready var astronauta: Astronauta = $Astronauta
@onready var barra: Sprite2D = get_node_or_null("Barra")  # opcional por ahora
@onready var mensaje: Label = $Mensaje
@onready var temporizador: Timer = $TemporizadorSpawn

var cola: Array[String] = []
var aciertos := 0
var errores := 0
var resueltas := 0
var terminado := false
var puede_reiniciar := false  # solo en modo prueba (F6)

func _ready() -> void:
	# Sigue funcionando aunque la sala pause el árbol
	process_mode = Node.PROCESS_MODE_ALWAYS
	astronauta.bolita_atrapada.connect(_on_bolita_atrapada)
	temporizador.timeout.connect(_on_spawn)
	if es_prueba():
		finished.connect(func(r): print("finished con result = ", r))
	start()

func es_prueba() -> bool:
	# true cuando lo corres solo con F6 (sin sala)
	return get_tree().current_scene == self

func start() -> void:
	aciertos = 0
	errores = 0
	resueltas = 0
	terminado = false
	puede_reiniciar = false
	cola.clear()
	for i in num_oxigeno:
		cola.append("O")
	for i in total_bolitas - num_oxigeno:
		cola.append("H")
	cola.shuffle()
	mensaje.visible = false
	if barra:
		barra.frame = 10
	astronauta.position.x = 320
	astronauta.activo = true
	temporizador.wait_time = separacion
	temporizador.start()
	_on_spawn()

func _on_spawn() -> void:
	if cola.is_empty():
		temporizador.stop()
		return
	var b: Bolita = escena_bolita.instantiate()
	b.tipo = cola.pop_back()
	b.velocidad = velocidad_caida
	b.position = Vector2(randf_range(16, 624), -12)
	b.llego_al_suelo.connect(_on_bolita_resuelta)
	add_child(b)

func _on_bolita_atrapada(tipo: String) -> void:
	if terminado:
		return
	if tipo == "O":
		aciertos += 1
		if barra:
			barra.frame = clampi(10 - aciertos, 0, 10)
	else:
		errores += 1
	_on_bolita_resuelta()

func _on_bolita_resuelta() -> void:
	if terminado:
		return
	resueltas += 1
	if resueltas >= total_bolitas:
		terminar()

func terminar() -> void:
	terminado = true
	astronauta.activo = false
	temporizador.stop()
	var gano := aciertos >= aciertos_para_ganar
	await get_tree().create_timer(segundos_mensaje).timeout  # deja ver el último acierto
	cerrar(1.0 if gano else 0.5)

func abandonar() -> void:
	# Esc a la mitad: cuenta como perder
	terminado = true
	astronauta.activo = false
	temporizador.stop()
	cerrar(0.5)

func cerrar(resultado: float) -> void:
	# Avisa el resultado y cierra el minijuego (vuelve a la sala que lo abrió)
	finished.emit(resultado)
	if es_prueba():
		get_tree().quit()  # con F6 no hay sala a la que volver
	else:
		queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not terminado:
		abandonar()
