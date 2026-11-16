extends Node
## Escena principal: menú LOBEL -> cinemática -> juego -> final -> menú.
## También cambia de sala cuando el jugador usa una puerta (ver core/door.gd).

## El vestíbulo es el centro: desde ahí se llega a las otras tres salas.
const ROOMS := {
	&"lobby": {"scene": "res://rooms/lobby/lobby.tscn", "name": "Vestíbulo"},
	&"rest_room": {"scene": "res://rooms/rest_room/rest_room.tscn", "name": "Dormitorio"},
	&"operations": {"scene": "res://rooms/operations/operations.tscn", "name": "Sala de operaciones"},
	&"greenhouse": {"scene": "res://rooms/greenhouse/greenhouse.tscn", "name": "Invernadero y cocina"},
}
## Dónde aparece el jugador según la sala de la que viene: junto a la puerta
## por la que acaba de entrar.
const SPAWNS := {
	&"lobby": {
		&"rest_room": Vector2(52, 285),
		&"greenhouse": Vector2(594, 285),
		&"operations": Vector2(320, 322),
	},
	&"rest_room": {&"lobby": Vector2(60, 172)},
	&"operations": {&"lobby": Vector2(80, 172)},
	&"greenhouse": {&"lobby": Vector2(336, 316)},
}
const START_ROOM := &"lobby"
const MENU_SCENE := preload("res://menu/main_menu.tscn")
const ENDING_SCENE := preload("res://cutscene/ending.tscn")

## La cinemática de introducción solo se ve la primera vez que se presiona Iniciar.
@export var play_intro := true

@onready var _world: Node2D = $World
@onready var _hud: Hud = $HUD

var _room: Node
var _room_id: StringName
var _intro_seen := false
var _menu: CanvasLayer


func _ready() -> void:
	add_to_group(&"game")
	_hud.retry_requested.connect(start_game)
	_hud.title_requested.connect(go_to_menu)
	GameState.victory.connect(_on_victory)
	go_to_menu()


func go_to_menu() -> void:
	get_tree().paused = false
	_clear_room()
	GameState.new_game()   # deja el reloj pausado hasta la próxima partida
	_hud.hide_all()
	_menu = MENU_SCENE.instantiate()
	_menu.play_cutscene = play_intro and not _intro_seen
	_menu.start_game.connect(_on_menu_start)
	add_child(_menu)


func _on_menu_start(_intro_skipped: bool) -> void:
	_intro_seen = true
	_menu = null   # el menú se elimina solo (free_on_finish)
	start_game()


func start_game() -> void:
	get_tree().paused = false
	GameState.new_game()
	_room_id = &""
	change_room(START_ROOM)
	_hud.show_game(ROOMS[START_ROOM]["name"])
	TimeManager.resume_clock(&"init")
	_hud.show_toast("Día 1: mantén a Claudio con vida")


func _on_victory() -> void:
	get_tree().paused = true   # la cinemática sigue (PROCESS_MODE_ALWAYS)
	_hud.hide_all()
	var ending := ENDING_SCENE.instantiate()
	ending.finished.connect(_on_ending_finished)
	add_child(ending)


func _on_ending_finished(_skipped: bool) -> void:
	go_to_menu()


func change_room(room_id: StringName) -> void:
	if not ROOMS.has(room_id):
		push_error("Main.change_room: sala desconocida '%s'" % room_id)
		return
	var from := _room_id
	_clear_room()
	_room = load(ROOMS[room_id]["scene"]).instantiate()
	_room_id = room_id
	_world.add_child(_room)

	var player := _find_player(_room)
	var spawn: Variant = SPAWNS.get(room_id, {}).get(from)
	if player and spawn is Vector2:
		player.global_position = spawn
	_hud.player = player
	_hud.set_room_name(ROOMS[room_id]["name"])


func _clear_room() -> void:
	_hud.player = null
	if _room:
		_world.remove_child(_room)
		_room.queue_free()
		_room = null


func _find_player(node: Node) -> Player:
	if node is Player:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null
