extends Node
## Autoload "GameState": estados del astronauta, recursos de la estación,
## inventario, cultivo, game over y victoria.
##
## Regla de oro: ningún otro script cambia estas variables directamente.
## Todo pasa por las funciones de este archivo.


signal stat_changed(stat: StringName, value: float)
signal inventory_changed()
signal crop_changed()
signal message(text: String)
signal game_over(reason: String)
signal victory()
## Se emite cuando el descanso llega a 0 estando despierto.
## TimeManager lo escucha y lanza el desmayo cuando termina el paso de tiempo actual.
signal rest_depleted()


## Nombres que se muestran en los mensajes de "no alcanza".
const STAT_LABELS := {
	Balance.SATIETY: "saciedad",
	Balance.HYDRATION: "hidratación",
	Balance.REST: "descanso",
	Balance.WELLBEING: "bienestar",
	Balance.STATION_OXYGEN: "oxígeno",
	Balance.STATION_WATER: "agua",
	Balance.STATION_ENERGY: "energía",
}


var stats: Dictionary[StringName, float] = {}
var stat_max: Dictionary[StringName, float] = {}
var inventory: Dictionary[String, int] = {}

var crop_type: String = ""
var crop_planted_at: float = 0.0

## true tanto en game over como en victoria: el juego terminó.
var is_game_over := false
var is_victory := false

var radiation_active := false
## Alerta de radiación que llegó mientras dormía; se muestra al despertar.
var pending_alert: Dictionary = {}


func _ready() -> void:
	reset()


## Nueva partida completa (botón "Reintentar"): reinicia GameState y TimeManager.
func new_game() -> void:
	reset()
	TimeManager.reset()


## Pone todo en sus valores iniciales.
func reset() -> void:
	stats.clear()
	for stat: StringName in Balance.START_STATS:
		stats[stat] = Balance.START_STATS[stat]

	stat_max.clear()
	for stat: StringName in Balance.STAT_MAX:
		stat_max[stat] = Balance.STAT_MAX[stat]

	inventory.clear()
	for food_id: String in Balance.START_INVENTORY:
		inventory[food_id] = Balance.START_INVENTORY[food_id]

	crop_type = ""
	crop_planted_at = 0.0
	is_game_over = false
	is_victory = false
	radiation_active = false
	pending_alert = {}

	for stat: StringName in stats:
		stat_changed.emit(stat, stats[stat])
	inventory_changed.emit()
	crop_changed.emit()


# --- Estados ---------------------------------------------------------------

func get_stat(stat: StringName) -> float:
	return stats.get(stat, 0.0)


## Suma `amount` (puede ser negativo), limita entre 0 y el máximo,
## emite stat_changed y revisa avisos, game over y desmayo.
func change_stat(stat: StringName, amount: float) -> void:
	if is_game_over:
		return
	if not stats.has(stat):
		push_error("GameState.change_stat: estado desconocido '%s'" % stat)
		return

	var old_value: float = stats[stat]
	var new_value := clampf(old_value + amount, 0.0, stat_max[stat])
	if is_equal_approx(old_value, new_value):
		return

	stats[stat] = new_value
	stat_changed.emit(stat, new_value)
	_check_warnings(stat, old_value, new_value)

	if new_value <= 0.0 and old_value > 0.0:
		if Balance.FATAL_STATS.has(stat):
			trigger_game_over(Balance.FATAL_STATS[stat])
		elif stat == Balance.REST:
			rest_depleted.emit()


## Cambia el máximo de un estado (la radiación baja el del bienestar a 70).
func set_stat_max(stat: StringName, value: float) -> void:
	if not stat_max.has(stat):
		push_error("GameState.set_stat_max: estado desconocido '%s'" % stat)
		return
	stat_max[stat] = value
	if stats[stat] > value:
		change_stat(stat, value - stats[stat])


## Ej. can_afford({Balance.STATION_ENERGY: 5.0, Balance.STATION_WATER: 3.0})
func can_afford(costs: Dictionary) -> bool:
	for stat: StringName in costs:
		if get_stat(stat) < costs[stat]:
			return false
	return true


func spend(costs: Dictionary) -> void:
	for stat: StringName in costs:
		change_stat(stat, -costs[stat])


## Desgaste por tiempo. Solo lo llama TimeManager.
func apply_decay(hours: float, sleeping: bool) -> void:
	if is_game_over:
		return
	var column := 1 if sleeping else 0
	for stat: StringName in Balance.DECAY:
		var rate: float = Balance.DECAY[stat][column]
		if stat == Balance.SATIETY and is_low_wellbeing():
			rate *= Balance.LOW_WELLBEING_SATIETY_MULT
		elif stat == Balance.WELLBEING and radiation_active:
			rate *= Balance.RADIATION_WELLBEING_MULT
		change_stat(stat, -rate * hours)
		if is_game_over:
			return


func is_low_wellbeing() -> bool:
	return get_stat(Balance.WELLBEING) < Balance.LOW_WELLBEING_THRESHOLD


# --- Saciedad --------------------------------------------------------------

func get_satiety_state() -> String:
	var satiety := get_stat(Balance.SATIETY)
	if satiety >= Balance.SATIETY_SATISFIED_THRESHOLD:
		return Balance.SATIETY_STATE_SATISFIED
	elif satiety >= Balance.SATIETY_HUNGRY_THRESHOLD:
		return Balance.SATIETY_STATE_HUNGRY
	return Balance.SATIETY_STATE_STARVING


func get_action_satiety_cost() -> float:
	var satiety := get_stat(Balance.SATIETY)
	var cost := Balance.ACTION_SATIETY_COST_STARVING
	if satiety >= Balance.SATIETY_SATISFIED_THRESHOLD:
		cost = Balance.ACTION_SATIETY_COST_SATISFIED
	elif satiety >= Balance.SATIETY_HUNGRY_THRESHOLD:
		cost = Balance.ACTION_SATIETY_COST_HUNGRY
	if is_low_wellbeing():
		cost *= Balance.LOW_WELLBEING_SATIETY_MULT
	return cost


## Cobra saciedad si la acción está en SATIETY_COST_ACTIONS.
func apply_action_cost(action_id: String) -> void:
	if action_id in Balance.SATIETY_COST_ACTIONS:
		change_stat(Balance.SATIETY, -get_action_satiety_cost())


# --- Sala de operaciones y minijuegos --------------------------------------

## Llamar al abrir un minijuego ("electrolysis", "puzzle" o "ping_pong").
## Cobra el costo al empezar (salir a la mitad no regala recursos) y pausa el reloj.
## Devuelve false (y emite message) si no alcanza.
func start_minigame(action_id: String) -> bool:
	if is_game_over:
		return false
	match action_id:
		"electrolysis":
			var costs := {
				Balance.STATION_WATER: Balance.ELECTROLYSIS_WATER_COST,
				Balance.STATION_ENERGY: Balance.ELECTROLYSIS_ENERGY_COST,
			}
			if not _require(costs):
				return false
			spend(costs)
		"puzzle", "ping_pong":
			pass
		_:
			push_error("GameState.start_minigame: minijuego desconocido '%s'" % action_id)
			return false
	TimeManager.pause_clock(&"minigame")
	return true


## Llamar cuando el minijuego emite finished(result).
## Aplica la recompensa × result, cobra saciedad, avanza el tiempo y reanuda el reloj.
func finish_minigame(action_id: String, result: float) -> void:
	result = clampf(result, Balance.MINIGAME_MIN_RESULT, Balance.MINIGAME_MAX_RESULT)
	match action_id:
		"electrolysis":
			change_stat(Balance.STATION_OXYGEN, Balance.ELECTROLYSIS_OXYGEN * result)
		"puzzle":
			change_stat(Balance.STATION_ENERGY, Balance.PUZZLE_ENERGY * result)
		"ping_pong":
			change_stat(Balance.WELLBEING, lerpf(Balance.PING_PONG_MIN, Balance.PING_PONG_MAX, result))
		_:
			push_error("GameState.finish_minigame: minijuego desconocido '%s'" % action_id)
	apply_action_cost(action_id)
	TimeManager.advance_hours(Balance.ACTION_HOURS.get(action_id, 1.0))
	TimeManager.resume_clock(&"minigame")


## Acción simple con E (sin minijuego).
func filter_water() -> bool:
	if is_game_over:
		return false
	var costs := {Balance.STATION_ENERGY: Balance.FILTER_ENERGY_COST}
	if not _require(costs):
		return false
	spend(costs)
	change_stat(Balance.STATION_WATER, Balance.FILTER_WATER)
	apply_action_cost("filter_water")
	TimeManager.advance_hours(Balance.ACTION_HOURS["filter_water"])
	return true


# --- Invernadero -----------------------------------------------------------

func sow(crop_id: String) -> bool:
	if is_game_over:
		return false
	if not Balance.CROPS.has(crop_id):
		push_error("GameState.sow: cultivo desconocido '%s'" % crop_id)
		return false
	if crop_type != "":
		message.emit("Ya hay una planta en el invernadero")
		return false

	var crop: Dictionary = Balance.CROPS[crop_id]
	var costs := {
		Balance.STATION_ENERGY: Balance.SOW_ENERGY,
		Balance.STATION_WATER: crop["water"],
	}
	if not _require(costs):
		return false

	spend(costs)
	crop_type = crop_id
	crop_planted_at = TimeManager.total_hours
	crop_changed.emit()
	apply_action_cost("sow")
	TimeManager.advance_hours(Balance.ACTION_HOURS["sow"])
	return true


func is_crop_ready() -> bool:
	if crop_type == "":
		return false
	var grow_hours: float = Balance.CROPS[crop_type]["grow_hours"]
	return TimeManager.total_hours >= crop_planted_at + grow_hours


## Progreso de 0 a 1 para el sprite del cultivo.
func get_crop_progress() -> float:
	if crop_type == "":
		return 0.0
	var grow_hours: float = Balance.CROPS[crop_type]["grow_hours"]
	return clampf((TimeManager.total_hours - crop_planted_at) / grow_hours, 0.0, 1.0)


func harvest() -> bool:
	if is_game_over:
		return false
	if crop_type == "":
		message.emit("No hay nada sembrado")
		return false
	if not is_crop_ready():
		message.emit("La planta todavía no está lista")
		return false

	var costs := {Balance.STATION_ENERGY: Balance.HARVEST_ENERGY}
	if not _require(costs):
		return false

	spend(costs)
	var harvested := crop_type
	inventory[harvested] = inventory.get(harvested, 0) + 1
	crop_type = ""
	crop_planted_at = 0.0
	inventory_changed.emit()
	crop_changed.emit()
	change_stat(Balance.WELLBEING, Balance.HARVEST_WELLBEING)
	apply_action_cost("harvest")
	TimeManager.advance_hours(Balance.ACTION_HOURS["harvest"])
	return true


# --- Cocina ----------------------------------------------------------------

func get_food_count(food_id: String) -> int:
	return inventory.get(food_id, 0)


func is_full() -> bool:
	return get_stat(Balance.SATIETY) > Balance.FULL_WARNING


## Come un alimento del inventario. Si `heated`, usa el "Calentador de comida".
## Si ya está lleno, avisa pero deja comer de todos modos.
func eat(food_id: String, heated := false) -> bool:
	if is_game_over:
		return false
	if not Balance.FOODS.has(food_id):
		push_error("GameState.eat: alimento desconocido '%s'" % food_id)
		return false

	var food: Dictionary = Balance.FOODS[food_id]
	if get_food_count(food_id) <= 0:
		message.emit("No te queda %s" % food["name"])
		return false

	var costs := {}
	if heated:
		if not food["heatable"]:
			message.emit("%s no se puede calentar" % food["name"])
			return false
		costs[Balance.STATION_ENERGY] = Balance.HEAT_ENERGY
		if not _require(costs):
			return false

	if is_full():
		message.emit("Ya estás lleno")

	inventory[food_id] -= 1
	if inventory[food_id] <= 0:
		inventory.erase(food_id)
	inventory_changed.emit()

	if heated:
		spend(costs)
		change_stat(Balance.WELLBEING, Balance.HEAT_WELLBEING)
	change_stat(Balance.SATIETY, food["satiety"])
	apply_action_cost("eat")
	TimeManager.advance_hours(Balance.ACTION_HOURS["eat"])
	return true


func drink() -> bool:
	if is_game_over:
		return false
	var costs := {Balance.STATION_WATER: Balance.DRINK_WATER_COST}
	if not _require(costs):
		return false

	spend(costs)
	change_stat(Balance.HYDRATION, Balance.DRINK_HYDRATION)
	apply_action_cost("drink")
	TimeManager.advance_hours(Balance.ACTION_HOURS["drink"])
	return true


# --- Dormitorio ------------------------------------------------------------

func can_sleep() -> bool:
	var hour := TimeManager.get_hour()
	return (
		get_stat(Balance.REST) < Balance.SLEEP_MAX_REST
		or hour >= Balance.SLEEP_FROM_HOUR
		or hour < Balance.SLEEP_UNTIL_HOUR
	)


## Lo llama la cama. Devuelve false (y emite message) si no tiene sueño.
func sleep() -> bool:
	if is_game_over or TimeManager.is_sleeping:
		return false
	if not can_sleep():
		message.emit("No tienes sueño. Puedes dormir después de las 20:00")
		return false
	TimeManager.start_sleep()
	return true


# --- Radiación -------------------------------------------------------------

## La llama TimeManager.trigger_radiation().
func apply_radiation(penalty: float) -> void:
	change_stat(Balance.WELLBEING, -penalty)
	set_stat_max(Balance.WELLBEING, Balance.RADIATION_WELLBEING_MAX)
	radiation_active = true


# --- Fin del juego ---------------------------------------------------------

func trigger_game_over(reason: String) -> void:
	if is_game_over:
		return
	is_game_over = true
	game_over.emit(reason)


func trigger_victory() -> void:
	if is_game_over:
		return
	is_game_over = true
	is_victory = true
	victory.emit()


# --- Depuración ------------------------------------------------------------

func debug_fill() -> void:
	for stat: StringName in stats:
		change_stat(stat, stat_max[stat] - stats[stat])


# --- Internas --------------------------------------------------------------

## Como can_afford(), pero emite un mensaje con lo que falta.
func _require(costs: Dictionary) -> bool:
	for stat: StringName in costs:
		if get_stat(stat) < costs[stat]:
			message.emit("No hay suficiente %s en la estación" % STAT_LABELS.get(stat, String(stat)))
			return false
	return true


func _check_warnings(stat: StringName, old_value: float, new_value: float) -> void:
	var threshold := Balance.WARNING_THRESHOLD
	if stat == Balance.REST:
		threshold = Balance.LOW_REST_WARNING
	if not (old_value >= threshold and new_value < threshold):
		return
	if stat == Balance.REST:
		if not TimeManager.is_sleeping:
			message.emit("Estás muy cansado, ve a dormir")
	elif stat == Balance.STATION_WATER:
		message.emit("Agua de la estación baja")
	elif stat == Balance.STATION_ENERGY:
		message.emit("Energía de la estación baja")
