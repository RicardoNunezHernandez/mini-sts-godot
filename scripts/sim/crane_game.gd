class_name CraneGame
extends RefCounted
## Reglas del ejercicio de entrenamiento: tareas de descarga barco → muelle,
## validación de twistlocks y puntuación.

enum Phase { PICK, DELIVER, DONE }
enum Level { INFO, OK, WARNING, ERROR }

signal message(text: String, level: Level)

const JOBS_PER_SESSION := 5
## Penalizaciones de la puntuación (sobre 1000 puntos por tarea).
const POINTS_PER_SECOND := 3.0
const POINTS_PER_COLLISION := 150.0
const POINTS_PER_HARD_LANDING := 75.0
const POINTS_PER_METER_ERROR := 300.0

var yard: Yard
var model: CraneModel
var phase: Phase = Phase.PICK
var job_index := 0
var job_container := ""
var job_target: Yard.Stack
var job_time := 0.0
var total_time := 0.0
## Una entrada por tarea terminada: container, time, collisions, hard_landings, error, score.
var results: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _job_start_collisions := 0
var _job_start_hard_landings := 0


func start(rng_seed: int) -> void:
	_rng.seed = rng_seed
	yard = Yard.new()
	yard.build_default(rng_seed)
	model = CraneModel.new(yard)
	model.impact.connect(_on_impact)
	results.clear()
	job_index = 0
	total_time = 0.0
	_next_job()


func update(gantry_cmd: float, trolley_cmd: float, hoist_cmd: float, dt: float) -> void:
	model.step(gantry_cmd, trolley_cmd, hoist_cmd, dt)
	if phase != Phase.DONE:
		job_time += dt
		total_time += dt


## Acción del botón de twistlocks: cierra si el spreader va vacío, abre si va cargado.
func toggle_lock() -> bool:
	if phase == Phase.DONE:
		message.emit("Ejercicio terminado. Pulsa F5 para repetirlo.", Level.INFO)
		return false
	if model.carried_id == "":
		return _try_lock()
	return _try_unlock()


func _try_lock() -> bool:
	var stack := model.find_lock_candidate()
	if stack == null:
		message.emit("No cierra: el spreader debe estar apoyado y alineado sobre un contenedor.", Level.WARNING)
		return false
	var top: String = stack.containers.back()
	if top != job_container:
		message.emit("Ese es %s; la tarea pide %s." % [top, job_container], Level.WARNING)
		return false
	model.lock(stack)
	phase = Phase.DELIVER
	message.emit("Twistlocks cerrados: %s. Llévalo a %s." % [job_container, job_target.label], Level.OK)
	return true


func _try_unlock() -> bool:
	var stack := model.find_place_candidate()
	if stack == null:
		message.emit("No abre: el contenedor debe estar apoyado y alineado en una posición.", Level.WARNING)
		return false
	if stack != job_target:
		message.emit("Posición equivocada: el destino es %s." % job_target.label, Level.WARNING)
		return false
	var error := model.alignment_to(stack)
	model.unlock(stack)
	_finish_job(absf(error.x) + absf(error.y))
	return true


func _finish_job(error: float) -> void:
	var collisions := model.collisions - _job_start_collisions
	var hard_landings := model.hard_landings - _job_start_hard_landings
	var score := 1000.0 \
		- POINTS_PER_SECOND * job_time \
		- POINTS_PER_COLLISION * collisions \
		- POINTS_PER_HARD_LANDING * hard_landings \
		- POINTS_PER_METER_ERROR * error
	var result := {
		"container": job_container,
		"time": job_time,
		"collisions": collisions,
		"hard_landings": hard_landings,
		"error": error,
		"score": maxi(roundi(score), 0),
	}
	results.append(result)
	message.emit("%s entregado: %d puntos." % [job_container, result.score], Level.OK)
	job_index += 1
	_next_job()


func _next_job() -> void:
	if job_index >= JOBS_PER_SESSION:
		phase = Phase.DONE
		job_container = ""
		job_target = null
		message.emit("Ejercicio terminado: %d puntos." % total_score(), Level.OK)
		return
	var sources := yard.stacks.filter(func(s: Yard.Stack) -> bool: return s.on_ship and not s.containers.is_empty())
	var targets := yard.stacks.filter(func(s: Yard.Stack) -> bool: return not s.on_ship and s.containers.size() < Yard.MAX_LANE_TIERS)
	var source: Yard.Stack = sources[_rng.randi() % sources.size()]
	job_container = source.containers.back()
	job_target = targets[_rng.randi() % targets.size()]
	phase = Phase.PICK
	job_time = 0.0
	_job_start_collisions = model.collisions
	_job_start_hard_landings = model.hard_landings
	message.emit("Tarea %d/%d: recoge %s en %s." % [job_index + 1, JOBS_PER_SESSION, job_container, source.label], Level.INFO)


## Pila a la que hay que ir ahora: la del contenedor a recoger o el destino.
func current_goal() -> Yard.Stack:
	match phase:
		Phase.PICK:
			return yard.stack_of(job_container)
		Phase.DELIVER:
			return job_target
	return null


func total_score() -> int:
	var total := 0
	for result in results:
		total += int(result.score)
	return total


func _on_impact(kind: String, speed: float) -> void:
	if kind == "side":
		message.emit("¡Golpe lateral a %.1f m/s! (-%d)" % [speed, POINTS_PER_COLLISION], Level.ERROR)
	else:
		message.emit("Apoyo brusco a %.1f m/s (-%d). Baja más lento al final." % [speed, POINTS_PER_HARD_LANDING], Level.ERROR)
