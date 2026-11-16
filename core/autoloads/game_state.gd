extends Node
## Autoload "GameState": estados del astronauta, recursos de la estación,
## inventario, cultivo, game over y victoria.
##
## Regla de oro: ningún otro script cambia estas variables directamente.
## Todo pasa por las funciones de este archivo.


signal stat_changed(stat: StringName, value: float)
signal inventory_changed()
## Se emite cuando una maceta cambia (se siembra, se cosecha o se reinicia).
signal crop_changed(plot: int)
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

## Macetas del invernadero (Balance.PLOT_COUNT). Cada una es
## {"type": Balance.CropType, "planted_at": float (TimeManager.total_hours)}.
## Usar las funciones de la sección Invernadero, no leer esto directo.
var plots: Array[Dictionary] = []

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

	plots.clear()
	for i in Balance.PLOT_COUNT:
		plots.append(_empty_plot())
	is_game_over = false
	is_victory = false
	radiation_active = false
	pending_alert = {}

	for stat: StringName in stats:
		stat_changed.emit(stat, stats[stat])
	inventory_changed.emit()
	for i in Balance.PLOT_COUNT:
		crop_changed.emit(i)


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
		if TimeManager.is_fainted and Balance.FATAL_STATS.has(stat):
			_drop_with_floor(stat, rate * hours)
		else:
			change_stat(stat, -rate * hours)
		if is_game_over:
			return

	# La tormenta también desgasta los sistemas de la estación.
	if radiation_active:
		change_stat(Balance.STATION_OXYGEN, -Balance.STORM_OXYGEN_DRAIN * hours)
		if is_game_over:
			return
		change_stat(Balance.STATION_ENERGY, -Balance.STORM_ENERGY_DRAIN * hours)


## Castigo del desmayo. La saciedad respeta la red de seguridad (no mata).
func apply_faint_penalty() -> void:
	_drop_with_floor(Balance.SATIETY, Balance.FAINT_SATIETY_PENALTY)
	change_stat(Balance.WELLBEING, -Balance.FAINT_WELLBEING_PENALTY)


## Baja `amount` sin pasar de FAINT_VITAL_FLOOR (si ya estaba debajo, no baja más).
func _drop_with_floor(stat: StringName, amount: float) -> void:
	var current := get_stat(stat)
	var floor_value := minf(current, Balance.FAINT_VITAL_FLOOR)
	var target := maxf(current - amount, floor_value)
	change_stat(stat, target - current)


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

## Llamar al abrir un minijuego:
## "electrolysis", "oxygen", "filter_water", "maze", "ping_pong" o "exercise".
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
		"oxygen":
			var costs := {
				Balance.STATION_WATER: Balance.OXYGEN_WATER_COST,
				Balance.STATION_ENERGY: Balance.OXYGEN_ENERGY_COST,
			}
			if not _require(costs):
				return false
			spend(costs)
		"exercise":
			# Cansa al astronauta: cuesta descanso, no recursos de la estación.
			if get_stat(Balance.REST) < Balance.EXERCISE_REST_COST:
				message.emit("Estás muy cansado para hacer ejercicio")
				return false
			change_stat(Balance.REST, -Balance.EXERCISE_REST_COST)
		"filter_water":
			var costs := {Balance.STATION_ENERGY: Balance.FILTER_ENERGY_COST}
			if not _require(costs):
				return false
			spend(costs)
		"maze", "ping_pong":
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
		"oxygen":
			change_stat(Balance.STATION_OXYGEN, Balance.OXYGEN_REWARD * result)
		"maze":
			change_stat(Balance.STATION_ENERGY, Balance.MAZE_ENERGY * result)
		"filter_water":
			change_stat(Balance.STATION_WATER, Balance.FILTER_WATER * result)
		"ping_pong":
			change_stat(Balance.WELLBEING, lerpf(Balance.PING_PONG_MIN, Balance.PING_PONG_MAX, result))
		"exercise":
			change_stat(Balance.WELLBEING, lerpf(Balance.EXERCISE_MIN, Balance.EXERCISE_MAX, result))
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
## El cultivo crece solo con el tiempo: el progreso se calcula con
## TimeManager.total_hours, así sigue creciendo mientras Claudio duerme o
## hace minijuegos. El agua se cobra completa al sembrar.

## Siembra `type` en la maceta `plot`. Cobra energía y el agua del cultivo.
func sow(plot: int, type: Balance.CropType) -> bool:
	if is_game_over or not _is_valid_plot(plot):
		return false
	if not Balance.CROPS.has(type):
		push_error("GameState.sow: cultivo desconocido '%s'" % type)
		return false
	if get_plot_type(plot) != Balance.CropType.NONE:
		message.emit("Esta maceta ya tiene una planta")
		return false

	var crop: Dictionary = Balance.CROPS[type]
	var costs := {
		Balance.STATION_ENERGY: Balance.SOW_ENERGY,
		Balance.STATION_WATER: crop["water"],
	}
	if not _require(costs):
		return false

	spend(costs)
	plots[plot] = {"type": type, "planted_at": TimeManager.total_hours}
	crop_changed.emit(plot)
	message.emit("Sembraste %s" % String(crop["name"]).to_lower())
	apply_action_cost("sow")
	TimeManager.advance_hours(Balance.ACTION_HOURS["sow"])
	return true


## Cosecha la maceta `plot` si está lista: suma `yield` unidades al inventario.
func harvest(plot: int) -> bool:
	if is_game_over or not _is_valid_plot(plot):
		return false
	var type := get_plot_type(plot)
	if type == Balance.CropType.NONE:
		message.emit("No hay nada sembrado")
		return false
	if not is_crop_ready(plot):
		message.emit("El cultivo de %s aún no está listo (faltan %d h)" % [
			get_crop_name(plot).to_lower(), ceili(get_hours_left(plot))])
		return false

	var costs := {Balance.STATION_ENERGY: Balance.HARVEST_ENERGY}
	if not _require(costs):
		return false

	spend(costs)
	var crop: Dictionary = Balance.CROPS[type]
	var food_id: String = crop["food_id"]
	var amount: int = crop["yield"]
	inventory[food_id] = inventory.get(food_id, 0) + amount
	plots[plot] = _empty_plot()
	inventory_changed.emit()
	crop_changed.emit(plot)
	message.emit("Cosechaste %d × %s" % [amount, crop["name"]])
	change_stat(Balance.WELLBEING, crop["harvest_wellbeing"])
	apply_action_cost("harvest")
	TimeManager.advance_hours(Balance.ACTION_HOURS["harvest"])
	return true


func get_plot_type(plot: int) -> Balance.CropType:
	if not _is_valid_plot(plot):
		return Balance.CropType.NONE
	return plots[plot]["type"]


## Nombre del cultivo para mostrar ("" si la maceta está vacía).
func get_crop_name(plot: int) -> String:
	var type := get_plot_type(plot)
	if type == Balance.CropType.NONE:
		return ""
	return Balance.CROPS[type]["name"]


func is_crop_ready(plot: int) -> bool:
	return get_plot_type(plot) != Balance.CropType.NONE and get_hours_left(plot) <= 0.0


## Horas que faltan para cosechar (0 si está lista o vacía).
func get_hours_left(plot: int) -> float:
	var type := get_plot_type(plot)
	if type == Balance.CropType.NONE:
		return 0.0
	var grow_hours: float = Balance.CROPS[type]["grow_hours"]
	var planted_at: float = plots[plot]["planted_at"]
	return maxf(planted_at + grow_hours - TimeManager.total_hours, 0.0)


## Progreso de 0 a 1.
func get_crop_progress(plot: int) -> float:
	var type := get_plot_type(plot)
	if type == Balance.CropType.NONE:
		return 0.0
	var grow_hours: float = Balance.CROPS[type]["grow_hours"]
	return clampf(1.0 - get_hours_left(plot) / grow_hours, 0.0, 1.0)


## Etapa del sprite: 0 brote, 1 creciendo, 2 lista (-1 si está vacía).
## La última etapa solo aparece cuando ya se puede cosechar.
func get_crop_stage(plot: int) -> int:
	if get_plot_type(plot) == Balance.CropType.NONE:
		return -1
	if is_crop_ready(plot):
		return Balance.CROP_STAGES - 1
	if get_crop_progress(plot) >= Balance.CROP_GROWING_AT:
		return 1
	return 0


## true si alguna maceta está lista para cosechar.
func has_ready_crop() -> bool:
	for plot in plots.size():
		if is_crop_ready(plot):
			return true
	return false


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


## Come en el microondas: si el alimento se calienta y la estación tiene
## energía, lo calienta (−HEAT_ENERGY, +HEAT_WELLBEING). Las verduras, o la
## comida cuando no hay energía, se comen frías.
func eat_at_microwave(food_id: String) -> bool:
	if not Balance.FOODS.has(food_id):
		push_error("GameState.eat_at_microwave: alimento desconocido '%s'" % food_id)
		return false
	var heated := can_heat(food_id)
	if Balance.FOODS[food_id]["heatable"] and not heated and get_food_count(food_id) > 0:
		message.emit("No hay energía en la estación: se come sin calentar")
	return eat(food_id, heated)


## true si `food_id` se calienta y la estación tiene energía para hacerlo.
func can_heat(food_id: String) -> bool:
	return Balance.FOODS.has(food_id) and Balance.FOODS[food_id]["heatable"] \
		and can_afford({Balance.STATION_ENERGY: Balance.HEAT_ENERGY})


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

## Siempre se puede dormir: de noche duerme hasta las 06:00 y de día es una
## siesta de Balance.NAP_HOURS (ver TimeManager.start_sleep()).
func can_sleep() -> bool:
	return not is_game_over and not TimeManager.is_sleeping


## Lo llama la cama.
func sleep() -> bool:
	if not can_sleep():
		return false
	if not TimeManager.is_night():
		message.emit("Tomas una siesta de %d horas" % int(Balance.NAP_HOURS))
	TimeManager.start_sleep()
	return true


# --- Radiación -------------------------------------------------------------

## La llama TimeManager.trigger_radiation().
## Primera llamarada: empieza la tormenta, que ya no termina.
func apply_radiation(penalty: float) -> void:
	radiation_active = true
	set_stat_max(Balance.WELLBEING, Balance.RADIATION_WELLBEING_MAX)
	change_stat(Balance.WELLBEING, -penalty)


## Réplicas: pegan al bienestar mientras la tormenta sigue.
func apply_flare(penalty: float) -> void:
	change_stat(Balance.WELLBEING, -penalty)


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

func _empty_plot() -> Dictionary:
	return {"type": Balance.CropType.NONE, "planted_at": 0.0}


func _is_valid_plot(plot: int) -> bool:
	if plot < 0 or plot >= plots.size():
		push_error("GameState: maceta inválida %d" % plot)
		return false
	return true


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
