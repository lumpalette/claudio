class_name PlantPot
extends Interactable
## Maceta del invernadero. Muestra el cultivo de la maceta `plot_index` de
## GameState y, con el jugador cerca, al interactuar (E/Enter):
## - maceta vacía: abre el menú de siembra (CropMenu).
## - planta lista: cosecha directo.
## - planta creciendo: el aviso dice cuántas horas faltan.
##
## Solo escucha a GameState y TimeManager: los cambios pasan por GameState.
## El origen del nodo va en el borde inferior de la tierra (para el y-sort).

const TEXTURES := {
	Balance.CropType.LETTUCE: [
		preload("res://rooms/greenhouse/crops/lettuce_stage_0_ai.png"),
		preload("res://rooms/greenhouse/crops/lettuce_stage_1_ai.png"),
		preload("res://rooms/greenhouse/crops/lettuce_stage_2_ai.png"),
	],
	Balance.CropType.TOMATO: [
		preload("res://rooms/greenhouse/crops/tomato_stage_0_ai.png"),
		preload("res://rooms/greenhouse/crops/tomato_stage_1_ai.png"),
		preload("res://rooms/greenhouse/crops/tomato_stage_2_ai.png"),
	],
	Balance.CropType.CHILI: [
		preload("res://rooms/greenhouse/crops/chili_stage_0_ai.png"),
		preload("res://rooms/greenhouse/crops/chili_stage_1_ai.png"),
		preload("res://rooms/greenhouse/crops/chili_stage_2_ai.png"),
	],
}

## Maceta de GameState que representa (0 a Balance.PLOT_COUNT - 1).
@export_range(0, 5) var plot_index := 0
## Menú de siembra compartido por todas las macetas.
@export var crop_menu: CropMenu

@onready var _sprite: Sprite2D = $CropSprite

var _shown_type := -1
var _shown_stage := -2


func _ready() -> void:
	GameState.crop_changed.connect(_on_crop_changed)
	_refresh()


# --- Interactable ----------------------------------------------------------

func interact(_player: Player) -> bool:
	if GameState.get_plot_type(plot_index) != Balance.CropType.NONE:
		# Lista: cosecha. Creciendo: GameState avisa cuántas horas faltan.
		GameState.harvest(plot_index)
		_refresh()
		return false

	if crop_menu == null:
		push_warning("PlantPot %d: falta asignar crop_menu" % plot_index)
		return false

	crop_menu.closed.connect(_on_menu_closed, CONNECT_ONE_SHOT)
	crop_menu.open(plot_index)
	return true


func get_prompt() -> String:
	if GameState.is_crop_ready(plot_index):
		return "Cosechar %s" % GameState.get_crop_name(plot_index).to_lower()
	if GameState.get_plot_type(plot_index) != Balance.CropType.NONE:
		return "%s: faltan %dh" % [
			GameState.get_crop_name(plot_index), ceili(GameState.get_hours_left(plot_index))]
	return "Sembrar"


# --- Señales ---------------------------------------------------------------

func _on_menu_closed() -> void:
	_refresh()
	interaction_ended.emit()


func _on_crop_changed(plot: int) -> void:
	if plot == plot_index:
		_refresh()


## El sprite solo cambia cuando cambia la etapa, aunque el tiempo corra.
func _refresh() -> void:
	var type := GameState.get_plot_type(plot_index)
	var stage := GameState.get_crop_stage(plot_index)
	if type != _shown_type or stage != _shown_stage:
		_shown_type = type
		_shown_stage = stage
		_sprite.texture = null if stage < 0 else TEXTURES[type][stage]


func _process(_delta: float) -> void:
	# La etapa avanza sola con el tiempo (también mientras duerme).
	if GameState.get_plot_type(plot_index) != Balance.CropType.NONE:
		_refresh()
