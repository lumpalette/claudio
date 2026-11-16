extends Minigame
# Minijuego de ejercicio estilo runner: el astronauta corre solo y el nivel se
# mueve hacia la izquierda. Salta los pinchos con ESPACIO (o flecha arriba / W)
# hasta llegar a la bandera.
# NO habla con GameState ni TimeManager: solo emite finished(result) y se borra.


const TEXTURA_PINCHO := preload("assets/pincho.png")
const TEXTURA_PINCHOS3 := preload("assets/pinchos_x3.png")

@export var velocidad := 160.0        # px por segundo que avanza el nivel
@export var largo_nivel := 3000.0     # distancia hasta la bandera (más = dura más)
@export var separacion_min := 200.0   # espacio libre mínimo entre pinchos
@export var separacion_max := 320.0
@export var fuerza_salto := 300.0
@export var gravedad := 700.0
@export var fallos_maximos := 3
@export var x_astronauta := 70.0
@export var y_suelo := 328.0          # donde pisan los pies
@export var segundos_mensaje := 1.5

@onready var astronauta: Sprite2D = $Astronauta
@onready var mundo: Node2D = $Mundo
@onready var meta: Sprite2D = $Mundo/Meta
@onready var suelo1: Sprite2D = $Suelo1
@onready var suelo2: Sprite2D = $Suelo2
@onready var marcador: Label = $Marcador
@onready var mensaje: Label = $Mensaje
@onready var fondo: Sprite2D = $Fondo

var velocidad_y := 0.0
var en_suelo := true
var corriendo := false
var fallos := 0
var invulnerable := 0.0       # segundos sin poder chocar después de un tropiezo
var terminado := false
var puede_reiniciar := false  # solo en modo prueba (F6)
var tiempo_anim := 0.0

func _ready() -> void:
	# Sigue funcionando aunque la sala pause el árbol
	process_mode = Node.PROCESS_MODE_ALWAYS
	if es_prueba():
		finished.connect(func(r): print("finished con result = ", r))
	start()

func es_prueba() -> bool:
	# true cuando lo corres solo con F6 (sin sala)
	return get_tree().current_scene == self

func y_centro() -> float:
	# Altura del centro del astronauta cuando pisa el suelo
	return y_suelo - astronauta.texture.get_height() / 2.0

func start() -> void:
	fallos = 0
	terminado = false
	puede_reiniciar = false
	invulnerable = 0.0
	mensaje.visible = false
	# Deja fondo, suelos y mundo en su lugar sin depender del Inspector
	fondo.centered = false
	fondo.position = Vector2.ZERO
	suelo1.centered = false
	suelo2.centered = false
	suelo1.position = Vector2(0.0, y_suelo)
	suelo2.position = Vector2(640.0, y_suelo)
	mundo.position = Vector2.ZERO
	mundo.scale = Vector2.ONE
	generar_nivel()
	astronauta.modulate = Color.WHITE
	astronauta.position = Vector2(x_astronauta, y_centro())
	astronauta.frame = 0  # quieto
	velocidad_y = 0.0
	en_suelo = true
	corriendo = false
	actualizar_marcador(0.0)
	await get_tree().create_timer(0.8).timeout  # pausa antes de arrancar
	if not terminado:
		corriendo = true

func generar_nivel() -> void:
	# Quita los pinchos anteriores y crea nuevos hasta la bandera
	for o in mundo.get_children():
		if o != meta:
			o.queue_free()
	var x := 400.0  # tramo libre al inicio
	while x < largo_nivel - 250.0:
		var triple := randf() < 0.4
		var tex: Texture2D = TEXTURA_PINCHOS3 if triple else TEXTURA_PINCHO
		var p := Sprite2D.new()
		p.texture = tex
		p.position = Vector2(x + tex.get_width() / 2.0, y_suelo - tex.get_height() / 2.0)
		mundo.add_child(p)
		x += tex.get_width() + randf_range(separacion_min, separacion_max)
	meta.position = Vector2(largo_nivel, y_suelo - meta.texture.get_height() / 2.0)
	print("pinchos creados: ", mundo.get_child_count() - 1, "  meta en: ", meta.position)


func _unhandled_input(event: InputEvent) -> void:
	if terminado:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("move_up"):
		saltar()
		get_viewport().set_input_as_handled()
	#elif event.is_action_pressed("pause"):
	#	abandonar()
	#	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if terminado or not corriendo:
		return

	# El nivel y el suelo avanzan hacia la izquierda
	var avance := velocidad * delta
	mundo.position.x -= avance
	for s in [suelo1, suelo2]:
		s.position.x -= avance
		if s.position.x <= -640.0:
			s.position.x += 1280.0  # el suelo se recicla

	# Salto y gravedad
	velocidad_y += gravedad * delta
	astronauta.position.y += velocidad_y * delta
	if astronauta.position.y >= y_centro():
		astronauta.position.y = y_centro()
		velocidad_y = 0.0
		en_suelo = true

	# Animación: pasos en el suelo, salto en el aire
	if en_suelo:
		tiempo_anim += delta
		astronauta.frame = 1 + int(tiempo_anim / 0.12) % 2
	else:
		astronauta.frame = 3

	# Tropiezo: mientras parpadea no puede chocar otra vez
	if invulnerable > 0.0:
		invulnerable -= delta
		astronauta.modulate.a = 0.35 if int(invulnerable * 12.0) % 2 == 0 else 1.0
		if invulnerable <= 0.0:
			astronauta.modulate = Color.WHITE
	else:
		var caja := caja_astronauta()
		for o in mundo.get_children():
			var pincho := o as Sprite2D
			if pincho == null or pincho == meta:
				continue
			if absf(pincho.global_position.x - astronauta.position.x) > 40.0:
				continue  # muy lejos, no hace falta revisar
			if caja.intersects(caja_pincho(pincho)):
				chocar()
				break
		if terminado:
			return

	# Progreso y meta
	var falta := meta.global_position.x - astronauta.position.x
	var progreso := clampf(1.0 - falta / (largo_nivel - x_astronauta), 0.0, 1.0)
	actualizar_marcador(progreso)
	if falta - 8.0 <= 0.0:
		terminar(true)

func caja_astronauta() -> Rect2:
	# Caja un poco más chica que el dibujo, para que sea justo
	return Rect2(astronauta.position + Vector2(-6, -13), Vector2(12, 28))

func caja_pincho(p: Sprite2D) -> Rect2:
	var tam := p.texture.get_size()
	var caja := Rect2(p.global_position - tam / 2.0, tam)
	return caja.grow_individual(-3, -4, -3, 0)  # más justa que el dibujo

func saltar() -> void:
	if corriendo and en_suelo:
		velocidad_y = -fuerza_salto
		en_suelo = false

func chocar() -> void:
	fallos += 1
	astronauta.modulate = Color(1, 0.4, 0.4)  # se pone rojo
	if fallos >= fallos_maximos:
		terminar(false)
	else:
		invulnerable = 1.2

func actualizar_marcador(progreso: float) -> void:
	marcador.text = "Meta: %d%%     Tropiezos: %d/%d" % [int(progreso * 100.0), fallos, fallos_maximos]

func terminar(gano: bool) -> void:
	terminado = true
	corriendo = false
	await get_tree().create_timer(segundos_mensaje).timeout  # deja ver el tropiezo o la meta
	cerrar(1.0 if gano else 0.5)

func abandonar() -> void:
	terminado = true
	corriendo = false
	cerrar(0.5)

func cerrar(resultado: float) -> void:
	# Avisa el resultado y cierra el minijuego (vuelve a la sala que lo abrió)
	finished.emit(resultado)
	if es_prueba():
		get_tree().quit()  # con F6 no hay sala a la que volver
	else:
		queue_free()
