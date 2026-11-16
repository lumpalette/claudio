class_name Player
extends CharacterBody2D


enum Direction {
	DOWN,
	RIGHT,
	UP,
	LEFT,
}


@export var direction: Direction

@export_group("Nodes")
@export var animator: AnimatedSprite2D
@export var interactor: Area2D
@export var state: StateMachine

@export_group("Physics")
@export var max_speed: float
@export var acceleration: float
@export var friction: float

var current_interaction: Interactable


func get_closest_interactable() -> Interactable:
	var closest: Interactable = null
	var best := INF
	for area in interactor.get_overlapping_areas():
		if area is Interactable:
			var d := global_position.distance_squared_to(area.global_position)
			if d < best:
				best = d
				closest = area

	return closest


func try_interact() -> bool:
	if not Input.is_action_just_pressed("interact"):
		return false

	var target := get_closest_interactable()
	if target == null:
		return false

	if target.interact(self):
		current_interaction = target
		state.set_state("wait")
		return true

	return false


static func get_direction_from_vector(vector: Vector2, deadzone: float, fallback: Direction) -> Direction:
	# I want to priorize the X-axis for whatever reason xd.
	if vector.x > deadzone:
		return Direction.RIGHT
	elif vector.x < -deadzone:
		return Direction.LEFT

	if vector.y < -deadzone:
		return Direction.UP
	elif vector.y > deadzone:
		return Direction.DOWN

	# For zero vectors, we return an invalid direction because idk
	return fallback


static func get_direction_name(dir: Direction) -> StringName:
	match dir:
		Player.Direction.DOWN:
			return &"down"
		Player.Direction.RIGHT:
			return &"right"
		Player.Direction.UP:
			return &"up"
		Player.Direction.LEFT:
			return &"left"
	
	return &""
