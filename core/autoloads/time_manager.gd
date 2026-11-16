extends Node
## Autoload "TimeManager": reloj, saltos de tiempo, sueño, desmayo,
## radiación y victoria.
##
## Todo el tiempo vive en total_hours (horas desde el día 1 a las 00:00).
## El día y la hora se calculan a partir de ella, así nunca se desincronizan.
##
## Registrar DESPUÉS de GameState en la lista de autoloads.


signal time_changed(day: int, hour: float)
signal day_changed(day: int)
signal radiation_started(event: Dictionary)
## Cada llamarada después de la primera, mientras dura la tormenta.
signal flare_struck(event: Dictionary, penalty: float)
signal sleep_started()
signal sleep_ended()
signal fainted()


var total_hours: float = Balance.START_HOUR
var is_sleeping := false
## true mientras dura el sueño del desmayo (GameState aplica la red de seguridad).
var is_fainted := false
## true desde que empieza la tormenta; ya no vuelve a false (dura hasta el final).
var radiation_triggered := false
## Hora en la que cae la próxima llamarada de la tormenta.
var _next_flare_hour := INF
## Día en el que empezó la tormenta (normalmente Balance.RADIATION_DAY, pero
## con la tecla de depuración puede empezar antes).
var _storm_start_day := 0

## El reloj corre si nadie lo pausó y el juego no terminó.
## Para pausar usa pause_clock(motivo) / resume_clock(motivo): así un menú que se
## cierra no reanuda el reloj mientras un minijuego sigue abierto.
## Asignar clock_running = false/true sigue funcionando (usa el motivo &"manual").
var clock_running: bool:
	get:
		return _pause_reasons.is_empty() and not GameState.is_game_over
	set(value):
		if value:
			resume_clock(&"manual")
		else:
			pause_clock(&"manual")

var _pause_reasons: Dictionary[StringName, bool] = {}
var _advancing := false
var _queued_hours := 0.0
var _faint_pending := false
var _flares: Array[Dictionary] = []


func _ready() -> void:
	GameState.rest_depleted.connect(_on_rest_depleted)
	_load_flares()
	reset()


func reset() -> void:
	total_hours = Balance.START_HOUR
	is_sleeping = false
	is_fainted = false
	radiation_triggered = false
	_next_flare_hour = INF
	_storm_start_day = 0
	_pause_reasons.clear()
	_advancing = false
	_queued_hours = 0.0
	_faint_pending = false
	time_changed.emit(get_day(), get_hour())
	pause_clock(&"init")


func _process(delta: float) -> void:
	if not clock_running or _advancing:
		return
	_apply_time(delta / Balance.SECONDS_PER_GAME_HOUR)
	_handle_pending_faint()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or GameState.is_game_over:
		return
	if _is_action(event, &"debug_skip_hour"):
		advance_hours(1.0)
	elif _is_action(event, &"debug_skip_day"):
		advance_hours(24.0)
	elif _is_action(event, &"debug_radiation"):
		trigger_radiation()
	elif _is_action(event, &"debug_fill"):
		GameState.debug_fill()


# --- Consultas -------------------------------------------------------------

func get_day() -> int:
	return int(total_hours / 24.0) + 1


func get_hour() -> float:
	return fmod(total_hours, 24.0)


## "Día X – HH:MM"
func get_clock_text() -> String:
	var hour := get_hour()
	var hours := int(hour)
	var minutes := int((hour - hours) * 60.0)
	return "Día %d – %02d:%02d" % [get_day(), hours, minutes]


# --- Pausa -----------------------------------------------------------------

## Motivos sugeridos: &"minigame", &"alert", &"base_panel", &"menu".
func pause_clock(reason: StringName) -> void:
	_pause_reasons[reason] = true


func resume_clock(reason: StringName) -> void:
	_pause_reasons.erase(reason)


func is_paused_by(reason: StringName) -> bool:
	return _pause_reasons.has(reason)


# --- Avance del tiempo -----------------------------------------------------

## Salto de tiempo (acciones, minijuegos, dormir). Avanza en pasos de TIME_STEP
## para que la radiación, los cultivos, el game over y la victoria ocurran a la
## hora correcta. Funciona aunque el reloj esté pausado.
func advance_hours(hours: float) -> void:
	if hours <= 0.0 or GameState.is_game_over:
		return
	if _advancing:
		# Alguien pidió otro salto mientras otro está en curso: se suma al actual.
		_queued_hours += hours
		return

	_advancing = true
	var remaining := hours
	while remaining > 0.0001 and not GameState.is_game_over:
		var step := minf(Balance.TIME_STEP, remaining)
		_apply_time(step)
		remaining -= step
		remaining += _queued_hours
		_queued_hours = 0.0
	_advancing = false

	_handle_pending_faint()


func _apply_time(hours: float) -> void:
	if GameState.is_game_over:
		return
	var old_day := get_day()

	# a. Desgaste
	GameState.apply_decay(hours, is_sleeping)
	if GameState.is_game_over:
		return

	# b. Sumar tiempo
	total_hours += hours
	time_changed.emit(get_day(), get_hour())

	# c. Cambio de día
	var day := get_day()
	if day != old_day:
		day_changed.emit(day)

	# d. Tormenta de radiación: la primera llamarada la empieza, y mientras
	#    dura caen réplicas cada Balance.RADIATION_FLARE_HOURS.
	if not radiation_triggered and total_hours >= Balance.RADIATION_HOUR:
		trigger_radiation()
	elif radiation_triggered and total_hours >= _next_flare_hour:
		_strike_flare()

	# e. Victoria (f. advance_hours se detiene solo porque is_game_over pasa a true)
	if total_hours >= Balance.VICTORY_HOUR:
		GameState.trigger_victory()


# --- Sueño y desmayo -------------------------------------------------------

## La llama GameState.sleep().
## De noche (SLEEP_FROM_HOUR a SLEEP_UNTIL_HOUR) duerme hasta SLEEP_UNTIL_HOUR:
## mientras más tarde se acueste, menos horas duerme y menos descanso recupera.
## De día es una siesta de NAP_HOURS.
func start_sleep() -> void:
	if is_sleeping or GameState.is_game_over:
		return
	if is_night():
		_sleep_until_wake()
	else:
		_sleep_for(Balance.NAP_HOURS)


func is_night() -> bool:
	var hour := get_hour()
	return hour >= Balance.SLEEP_FROM_HOUR or hour < Balance.SLEEP_UNTIL_HOUR


## true desde BEDTIME_HOUR hasta SLEEP_UNTIL_HOUR: ya debería estar dormido.
func is_past_bedtime() -> bool:
	var hour := get_hour()
	return hour >= Balance.BEDTIME_HOUR or hour < Balance.SLEEP_UNTIL_HOUR


## Horas que faltan para la próxima SLEEP_UNTIL_HOUR (06:00).
## Si ya son exactamente las 06:00, devuelve 24 (la del día siguiente).
func hours_until_wake() -> float:
	var hours := fposmod(Balance.SLEEP_UNTIL_HOUR - get_hour(), 24.0)
	return 24.0 if hours < 0.001 else hours


func _sleep_until_wake() -> void:
	_sleep_for(hours_until_wake(), true)


func _sleep_for(hours: float, snap_to_minute := false) -> void:
	is_sleeping = true
	sleep_started.emit()
	advance_hours(hours)
	if snap_to_minute and not GameState.is_game_over:
		# Evita que el redondeo de los pasos deje el reloj en 05:59.
		total_hours = roundf(total_hours * 60.0) / 60.0
		time_changed.emit(get_day(), get_hour())
	is_sleeping = false
	if GameState.is_game_over:
		return
	sleep_ended.emit()
	_show_pending_alert()


func _on_rest_depleted() -> void:
	if not is_sleeping:
		_faint_pending = true


## El desmayo nunca se lanza en medio de un paso de tiempo; se espera a que
## termine, para no meter un advance_hours dentro de otro.
func _handle_pending_faint() -> void:
	if not _faint_pending or _advancing or is_sleeping or GameState.is_game_over:
		return
	_faint_pending = false
	is_fainted = true
	fainted.emit()  # day/faint_screen muestra "Claudio tuvo que irse a dormir"
	GameState.apply_faint_penalty()
	# Se pierde el resto del día: duerme hasta las 06:00.
	_sleep_until_wake()
	is_fainted = false


# --- Radiación -------------------------------------------------------------

func trigger_radiation() -> void:
	if radiation_triggered or GameState.is_game_over:
		return
	radiation_triggered = true
	_storm_start_day = get_day()

	var event := _pick_flare()
	var flare_class := String(event.get("classType", "M")).left(1).to_upper()
	if not Balance.RADIATION_PENALTY.has(flare_class):
		flare_class = "M"
	event["class"] = flare_class
	event["alert_text"] = _build_alert_text(event)
	event["class_text"] = Balance.RADIATION_ALERT_TEXT[flare_class]

	GameState.apply_radiation(Balance.RADIATION_PENALTY[flare_class])
	_next_flare_hour = total_hours + Balance.RADIATION_FLARE_HOURS

	if is_sleeping:
		GameState.pending_alert = event
	else:
		_announce_radiation(event)


## true mientras la tormenta solar sigue encima de la estación.
func is_storm_active() -> bool:
	return radiation_triggered and not GameState.is_game_over


## Días que lleva la tormenta, contando el primero (1, 2, 3...).
func get_storm_day() -> int:
	if not radiation_triggered:
		return 0
	return get_day() - _storm_start_day + 1


## Cuántos días dura la tormenta: desde que empezó hasta el final de la misión.
func get_storm_total_days() -> int:
	if not radiation_triggered:
		return 0
	return maxi(Balance.TOTAL_DAYS - _storm_start_day + 1, 1)


## Una réplica: pega al bienestar y avisa, sin detener el juego.
func _strike_flare() -> void:
	_next_flare_hour = total_hours + Balance.RADIATION_FLARE_HOURS
	if GameState.is_game_over:
		return

	var event := _pick_flare()
	var flare_class := String(event.get("classType", "M")).left(1).to_upper()
	if not Balance.RADIATION_PENALTY.has(flare_class):
		flare_class = "M"
	event["class"] = flare_class
	event["alert_text"] = _build_alert_text(event)
	event["class_text"] = Balance.RADIATION_ALERT_TEXT[flare_class]

	var penalty: float = Balance.RADIATION_PENALTY[flare_class] * Balance.RADIATION_AFTERSHOCK_MULT
	GameState.apply_flare(penalty)
	flare_struck.emit(event, penalty)


## ui/alert debe llamar resume_clock(&"alert") al cerrar la alerta.
func _announce_radiation(event: Dictionary) -> void:
	pause_clock(&"alert")
	radiation_started.emit(event)


func _show_pending_alert() -> void:
	if GameState.pending_alert.is_empty():
		return
	var event: Dictionary = GameState.pending_alert
	GameState.pending_alert = {}
	_announce_radiation(event)


func _build_alert_text(event: Dictionary) -> String:
	return "Tormenta solar detectada – basada en la llamarada %s registrada por la NASA el %s" % [
		event.get("classType", "?"),
		_format_date(String(event.get("beginTime", ""))),
	]


## "2024-05-14T16:51Z" -> "14/05/2024"
func _format_date(iso: String) -> String:
	var parts := iso.left(10).split("-")
	if parts.size() != 3:
		return iso
	return "%s/%s/%s" % [parts[2], parts[1], parts[0]]


func _pick_flare() -> Dictionary:
	if _flares.is_empty():
		return Balance.FALLBACK_FLARE.duplicate()
	return _flares.pick_random().duplicate()


func _load_flares() -> void:
	_flares.clear()
	var path := Balance.DONKI_FILE_PATH
	if not FileAccess.file_exists(path):
		push_warning("TimeManager: no se encontró %s; se usará FALLBACK_FLARE" % path)
		return

	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Array):
		push_warning("TimeManager: %s no es una lista; se usará FALLBACK_FLARE" % path)
		return

	for entry: Variant in data:
		if not (entry is Dictionary):
			continue
		var class_type := String(entry.get("classType", ""))
		if class_type != "" and Balance.RADIATION_PENALTY.has(class_type.left(1).to_upper()):
			_flares.append(entry)

	if _flares.is_empty():
		push_warning("TimeManager: %s no tiene llamaradas válidas; se usará FALLBACK_FLARE" % path)


func _is_action(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)
