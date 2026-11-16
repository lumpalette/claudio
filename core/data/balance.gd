class_name Balance
extends RefCounted

## Statistics names.
const SATIETY := &"satiety"
const HYDRATION := &"hydration"
const REST := &"rest"
const WELLBEING := &"wellbeing"
const STATION_OXYGEN := &"station_oxygen"
const STATION_WATER := &"station_water"
const STATION_ENERGY := &"station_energy"

## HUD statistics.
const HUD_STATS: Array[StringName] = [SATIETY, HYDRATION, STATION_OXYGEN, WELLBEING]

## Vital statistics, from the player.
const FATAL_STATS := {
	SATIETY: "starvation",
	HYDRATION: "dehydration",
	STATION_OXYGEN: "suffocation",
}

## Initial states for statistics.
const START_STATS := {
	SATIETY: 100.0,
	HYDRATION: 100.0,
	REST: 100.0,
	WELLBEING: 100.0,
	STATION_OXYGEN: 100.0,
	STATION_WATER: 100.0,
	STATION_ENERGY: 100.0,
}

## Maximum quantity for all statistics.
const STAT_MAX := {
	SATIETY: 100.0,
	HYDRATION: 100.0,
	REST: 100.0,
	WELLBEING: 100.0,
	STATION_OXYGEN: 100.0,
	STATION_WATER: 100.0,
	STATION_ENERGY: 100.0,
}


## Time constants.
const DAY_LENGTH_SECONDS := 360.0  # demo: 120.0
const SECONDS_PER_GAME_HOUR := DAY_LENGTH_SECONDS / 24.0
const START_HOUR := 6.0
const TOTAL_DAYS := 7
const VICTORY_HOUR := TOTAL_DAYS * 24.0  # 168
## La tormenta solar empieza el día RADIATION_DAY a las 06:00 y dura hasta
## el final de la misión (ver la sección "Tormenta de radiación").
const RADIATION_DAY := 5
const RADIATION_HOUR := (RADIATION_DAY - 1) * 24.0 + 6.0  # 102
const TIME_STEP := 0.25

## Duration of every action.
const ACTION_HOURS := {
	"eat": 0.5,
	"drink": 0.5,
	"sow": 0.5,
	"harvest": 0.5,
	"electrolysis": 1.0,
	"oxygen": 1.0,
	"maze": 1.0,
	"filter_water": 1.0,
	"ping_pong": 1.0,
	"exercise": 1.0,
}

## Statistic decay when [awake, sleeping]. Negative means the stat goes up.
const DECAY := {
	SATIETY: [1.5, 0.6],
	HYDRATION: [3.5, 1.5],
	REST: [3.5, -10.0],
	WELLBEING: [2.0, 0.3],
	STATION_OXYGEN: [2.3, 2.2],
}


## Satiety and satisfaction constants.
const SATIETY_SATISFIED_THRESHOLD := 70.0  # >= 70 means satisfied.
const SATIETY_HUNGRY_THRESHOLD := 40.0     # >= 40 means you have hunger; < 40 means fatal
const SATIETY_STATE_SATISFIED := "Satisfecho"
const SATIETY_STATE_HUNGRY := "Con hambre"
const SATIETY_STATE_STARVING := "Hambriento"

## Satiety decay produced by performing actions.
const ACTION_SATIETY_COST_SATISFIED := 5.0
const ACTION_SATIETY_COST_HUNGRY := 7.0
const ACTION_SATIETY_COST_STARVING := 10.0
const SATIETY_COST_ACTIONS := ["electrolysis", "oxygen", "maze", "filter_water", "harvest"]

const LOW_WELLBEING_THRESHOLD := 40.0
const LOW_WELLBEING_SATIETY_MULT := 1.5

const WARNING_THRESHOLD := 20.0  # Barras del HUD parpadean; aviso de agua/energía
const LOW_REST_WARNING := 20.0   # "Estás muy cansado, ve a dormir"
const FULL_WARNING := 90.0       # "Ya estás lleno"


# Sleep constants.
## Acostarse entre SLEEP_FROM_HOUR y SLEEP_UNTIL_HOUR es "dormir de noche":
## duerme hasta SLEEP_UNTIL_HOUR, así que mientras más tarde, menos horas
## (y menos descanso, que sube 10 por hora según DECAY).
const SLEEP_FROM_HOUR := 20.0
const SLEEP_UNTIL_HOUR := 6.0   # hora a la que siempre se despierta
## Hora límite para dormir: desde aquí el reloj del HUD parpadea.
const BEDTIME_HOUR := 22.0
## Acostarse de día (fuera de la noche) es una siesta de duración fija.
const NAP_HOURS := 3.0

## Desmayo (descanso en 0): duerme hasta SLEEP_UNTIL_HOUR, se pierde el resto del día.
const FAINT_SATIETY_PENALTY := 10.0
const FAINT_WELLBEING_PENALTY := 50.0
## Mientras está desmayado, saciedad, hidratación y oxígeno no bajan de este valor.
const FAINT_VITAL_FLOOR := 10.0


# Operation constants.
const ELECTROLYSIS_WATER_COST := 10.0
const ELECTROLYSIS_ENERGY_COST := 5.0
const ELECTROLYSIS_OXYGEN := 50.0
const MAZE_ENERGY := 40.0
const FILTER_ENERGY_COST := 5.0
const FILTER_WATER := 35.0
const PING_PONG_MIN := 15.0
const PING_PONG_MAX := 25.0

## Minijuego "oxygen": genera oxígeno (mismos valores que la electrólisis).
const OXYGEN_WATER_COST := 10.0
const OXYGEN_ENERGY_COST := 5.0
const OXYGEN_REWARD := 50.0

## Minijuego "exercise": sube el bienestar y cuesta descanso.
const EXERCISE_MIN := 15.0
const EXERCISE_MAX := 25.0
const EXERCISE_REST_COST := 10.0

## Resultado de un minijuego: nunca 0, para que nadie se quede atorado.
const MINIGAME_MIN_RESULT := 0.5
const MINIGAME_MAX_RESULT := 1.0
const MINIGAME_FALLBACK_HOLD_SECONDS := 3.0  # "mantén presionada la E"


# --- Invernadero ---
## Tipo de cultivo de una maceta. NONE (0) = maceta vacía.
enum CropType { NONE, LETTUCE, CHILI, TOMATO }

## Número de macetas del invernadero (una planta por maceta).
const PLOT_COUNT := 6

## food_id: clave en FOODS y en el inventario (la saciedad vive solo en FOODS).
## water: agua de la estación que se cobra al sembrar.
## yield: unidades que se suman al inventario al cosechar.
## harvest_wellbeing: bienestar que da cosecharlo.
const CROPS := {
	CropType.LETTUCE: {
		"food_id": "lettuce", "name": "Lechuga",
		"grow_hours": 12.0, "water": 1.0, "yield": 3, "harvest_wellbeing": 5.0,
	},
	CropType.TOMATO: {
		"food_id": "tomato", "name": "Tomate enano",
		"grow_hours": 24.0, "water": 5.0, "yield": 2, "harvest_wellbeing": 5.0,
	},
	CropType.CHILI: {
		"food_id": "chili", "name": "Chile",
		"grow_hours": 48.0, "water": 3.0, "yield": 1, "harvest_wellbeing": 15.0,
	},
}
const SOW_ENERGY := 5.0
const HARVEST_ENERGY := 2.0
const CROP_STAGES := 3  # Etapas del sprite: 0 brote, 1 creciendo, 2 lista
## Fracción del crecimiento a partir de la cual se muestra la etapa 1.
const CROP_GROWING_AT := 0.5


# --- Cocina ---
const FOODS := {
	"chicken_soup": {"name": "Sopa de pollo", "satiety": 25.0, "heatable": true},
	"mac_and_cheese": {"name": "Macarrones con queso", "satiety": 20.0, "heatable": true},
	"scrambled_eggs": {"name": "Huevos revueltos", "satiety": 15.0, "heatable": true},
	"lettuce": {"name": "Lechuga", "satiety": 15.0, "heatable": false},
	"tomato": {"name": "Tomate enano", "satiety": 30.0, "heatable": false},
	"chili": {"name": "Chile", "satiety": 50.0, "heatable": false},
}
const HEAT_ENERGY := 5.0
const HEAT_WELLBEING := 5.0
const DRINK_WATER_COST := 10.0
const DRINK_HYDRATION := 40.0

const START_INVENTORY := {"chicken_soup": 2, "mac_and_cheese": 2, "scrambled_eggs": 2}


# --- Tormenta de radiación (DONKI) ---
## La tormenta empieza el día RADIATION_DAY y ya no se va: son los últimos
## días de la misión y los más difíciles. Mientras dura:
##   - el bienestar baja más rápido y su máximo queda en RADIATION_WELLBEING_MAX
##   - la estación pierde oxígeno y energía por hora (los sistemas sufren)
##   - cada RADIATION_FLARE_HOURS cae otra llamarada, más débil que la primera
const DONKI_FILE_PATH := "res://data/donki_flares.json"
const RADIATION_PENALTY := {"C": 20.0, "M": 30.0, "X": 40.0}
const RADIATION_ALERT_TEXT := {
	"C": "Llamarada débil (clase C)",
	"M": "Llamarada media (clase M)",
	"X": "Llamarada fuerte (clase X)",
}
const RADIATION_WELLBEING_MULT := 1.5
const RADIATION_WELLBEING_MAX := 70.0

## Desgaste extra por hora de la estación mientras dura la tormenta.
const STORM_OXYGEN_DRAIN := 1.0
const STORM_ENERGY_DRAIN := 1.5
## Horas entre una llamarada y la siguiente.
const RADIATION_FLARE_HOURS := 12.0
## Las llamaradas que siguen a la primera son réplicas: pegan menos.
const RADIATION_AFTERSHOCK_MULT := 0.4

## Evento de respaldo si el JSON falla o está vacío (clase M).
## TODO: reemplazar estos campos por un registro real de donki_flares.json.
const FALLBACK_FLARE := {
	"flrID": "FALLBACK",
	"classType": "M1.0",
	"beginTime": "2024-01-01T00:00Z",
	"peakTime": "2024-01-01T00:00Z",
}
