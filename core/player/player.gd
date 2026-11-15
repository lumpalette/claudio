class_name Player
extends CharacterBody2D


enum Direction {
	DOWN,
	RIGHT,
	UP,
	LEFT,
}


@export var animator: AnimatedSprite2D
@export var state: StateMachine
@export var direction: Direction

@export_group("Physics")
@export var max_speed: float
@export var acceleration: float
@export var friction: float


static func get_direction_from_vector(vector: Vector2, deadzone: float, fallback: Direction) -> Direction :
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
	@warning_ignore("int_as_enum_without_match")
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
