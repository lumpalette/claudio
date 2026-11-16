extends Node
## Escena principal: título -> cinemática -> juego -> fin -> reintentar.
## También cambia de sala cuando el jugador usa una puerta (ver core/door.gd).

const ROOMS := {
	&"rest_room": {"scene": "res://rooms/rest_room/rest_room.tscn", "name": "Dormitorio"},
	&"operations": {"scene": "res://rooms/operations/operations.tscn", "name": "Sala de operaciones"},
	&"greenhouse": {"scene": "res://rooms/greenhouse/greenhouse.tscn", "name": "Invernadero y cocina"},
}
## Dónde aparece el jugador según la sala de la que viene.
const SPAWNS := {
	&"rest_room": {&"operations": Vector2(44, 172)},
	&"operations": {&"rest_room": Vector2(60, 172), &"greenhouse": Vector2(588, 172)},
	&"greenhouse": {&"operations": Vector2(336, 316)},
}
const START_ROOM := &"rest_room"
const INTRO_SCENE := preload("res://cutscene/cutscene.tscn")

## La cinemática solo se ve la primera vez que se presiona "Jugar".
@export var play_intro := true

@onready var _world: Node2D = $World
@onready var _hud: Hud = $HUD

var _room: Node
var _room_id: StringName
var _intro_seen := false


func _ready() -> void:
	add_to_group(&"game")
	_hud.play_requested.connect(_on_play_requested)
	_hud.retry_requested.connect(start_game)
	_hud.title_requested.connect(go_to_title)


func _on_play_requested() -> void:
	_hud.hide_all()
	if not play_intro or _intro_seen:
		start_game()
		return
	var intro := INTRO_SCENE.instantiate()
	intro.finished.connect(_on_intro_finished)
	add_child(intro)


func _on_intro_finished(_skipped: bool) -> void:
	_intro_seen = true
	start_game()


func start_game() -> void:
	get_tree().paused = false
	GameState.new_game()
	_room_id = &""
	change_room(START_ROOM)
	_hud.show_game(ROOMS[START_ROOM]["name"])
	TimeManager.resume_clock(&"init")
	_hud.show_toast("Día 1: mantén a Claudio con vida")


func go_to_title() -> void:
	get_tree().paused = false
	_clear_room()
	GameState.new_game()   # deja el reloj pausado hasta la próxima partida
	_hud.show_title()


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
