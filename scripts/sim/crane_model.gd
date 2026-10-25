class_name CraneModel
extends RefCounted
## Modelo físico de una grúa pórtico de muelle (STS, ship-to-shore).
##
## No usa nodos ni gráficos: sólo números. Así se puede probar sin abrir la
## ventana del juego, portar a otro motor y ejecutar a paso fijo (la misma
## entrada produce siempre el mismo resultado).

## kind: "side" (golpe lateral) o "landing" (apoyo brusco). speed en m/s.
signal impact(kind: String, speed: float)

## Paso fijo de integración. Independiente de los FPS de la pantalla.
const SUBSTEP := 1.0 / 240.0
## Si un cuadro tarda demasiado se descarta el exceso en vez de simular a saltos.
const MAX_FRAME_TIME := 0.1
## Altura del punto de donde cuelgan los cables (parte baja del carro).
const TROLLEY_ANCHOR_Y := 35.0
const SPREADER_HEIGHT := 0.6
const HOIST_SPEED_EMPTY := 1.8
const HOIST_SPEED_LOADED := 1.2
## Desnivel máximo que se considera "apoyarse"; uno mayor es un choque lateral.
const STEP_TOLERANCE := 0.3
const HARD_LANDING_SPEED := 0.7
const SIDE_IMPACT_SPEED := 0.2
## Cable sobrante que activa el freno de cable flojo.
const SLACK_LIMIT := 0.3
## Tolerancias de las guías del spreader para poder cerrar o abrir los twistlocks.
const LOCK_TOLERANCE_X := 0.30
const LOCK_TOLERANCE_Z := 0.20
const SEAT_TOLERANCE := 0.15

var yard: Yard
## Traslación del pórtico a lo largo del muelle (eje X).
var gantry := AxisDrive.new(-30.0, 30.0, 1.5, 0.4, 0.0)
## Carro sobre la pluma, perpendicular al muelle (eje Z; negativo = mar).
var trolley := AxisDrive.new(-26.0, 22.0, 3.0, 0.7, 8.0)
## Izaje: la "posición" es la longitud de cable desenrollada.
var hoist := AxisDrive.new(3.0, 41.0, HOIST_SPEED_EMPTY, 0.9, 20.0)
var payload := RopeLoad.new()
## Contenedor enganchado ("" si el spreader va vacío).
var carried_id := ""
var resting := false
var side_contact := false
var collisions := 0
var hard_landings := 0
var _accumulator := 0.0


func _init(p_yard: Yard) -> void:
	yard = p_yard
	payload.place_at(anchor_position() + Vector3.DOWN * hoist.position)


## Avanza la simulación. Los comandos van de -1 a 1:
## gantry_cmd + = hacia +X, trolley_cmd + = hacia tierra, hoist_cmd + = subir.
func step(gantry_cmd: float, trolley_cmd: float, hoist_cmd: float, dt: float) -> void:
	_accumulator = minf(_accumulator + dt, MAX_FRAME_TIME)
	while _accumulator >= SUBSTEP:
		_accumulator -= SUBSTEP
		_substep(gantry_cmd, trolley_cmd, hoist_cmd, SUBSTEP)


func _substep(gantry_cmd: float, trolley_cmd: float, hoist_cmd: float, dt: float) -> void:
	# Detector de cable flojo: con la carga apoyada no se permite seguir soltando cable.
	if slack() > SLACK_LIMIT and hoist.velocity >= 0.0:
		hoist.brake()
		hoist_cmd = maxf(hoist_cmd, 0.0)
	gantry.step(gantry_cmd, dt)
	trolley.step(trolley_cmd, dt)
	hoist.step(-hoist_cmd, dt)

	var before := payload.position
	payload.integrate(dt)
	payload.constrain_to_rope(anchor_position(), hoist.position)
	_resolve_contacts(before, dt)


func _resolve_contacts(before: Vector3, dt: float) -> void:
	var offset := bottom_offset()
	var p := payload.position
	var horizontal_speed := Vector2(p.x - before.x, p.z - before.z).length() / dt
	var fall_speed := (before.y - p.y) / dt

	# 1) Choque lateral: el movimiento horizontal metió la carga en algo más alto.
	#    Se prueba conservar cada eje por separado para que pueda deslizar por la pared.
	var blocked_x := false
	var blocked_z := false
	if _penetrates(p, offset):
		if not _penetrates(Vector3(p.x, p.y, before.z), offset):
			blocked_z = true
			p.z = before.z
		elif not _penetrates(Vector3(before.x, p.y, p.z), offset):
			blocked_x = true
			p.x = before.x
		else:
			blocked_x = true
			blocked_z = true
			p.x = before.x
			p.z = before.z
	var touching_side := blocked_x or blocked_z
	if touching_side and not side_contact and horizontal_speed > SIDE_IMPACT_SPEED:
		collisions += 1
		impact.emit("side", horizontal_speed)
	side_contact = touching_side

	# 2) Apoyo vertical sobre suelo, cubierta o contenedores.
	var surface := yard.surface_height(_area(p))
	var landed := p.y - offset <= surface
	if landed:
		p.y = surface + offset
		if not resting and fall_speed > HARD_LANDING_SPEED:
			hard_landings += 1
			impact.emit("landing", fall_speed)
	resting = landed

	payload.position = p
	# En Verlet, igualar previous a position anula la velocidad en ese eje.
	if blocked_x or landed:
		payload.previous.x = p.x
	if blocked_z or landed:
		payload.previous.z = p.z
	if landed:
		payload.previous.y = p.y


func _penetrates(p: Vector3, offset: float) -> bool:
	return yard.surface_height(_area(p)) - (p.y - offset) > STEP_TOLERANCE


func _area(p: Vector3) -> Rect2:
	return Yard.footprint(p.x, p.z).grow(-0.05)


# --- Twistlocks -------------------------------------------------------------

## Pila sobre la que el spreader vacío está apoyado y alineado, o null.
func find_lock_candidate() -> Yard.Stack:
	if carried_id != "" or not resting:
		return null
	var stack := yard.stack_near(payload.position.x, payload.position.z, LOCK_TOLERANCE_X, LOCK_TOLERANCE_Z)
	if stack == null or stack.containers.is_empty():
		return null
	if absf(spreader_bottom() - stack.top_height()) > SEAT_TOLERANCE:
		return null
	return stack


## Pila donde el contenedor enganchado está apoyado y alineado, o null.
func find_place_candidate() -> Yard.Stack:
	if carried_id == "" or not resting:
		return null
	var stack := yard.stack_near(payload.position.x, payload.position.z, LOCK_TOLERANCE_X, LOCK_TOLERANCE_Z)
	if stack == null:
		return null
	if absf(load_bottom() - stack.top_height()) > SEAT_TOLERANCE:
		return null
	return stack


func lock(stack: Yard.Stack) -> void:
	carried_id = stack.containers.pop_back()
	hoist.max_speed = HOIST_SPEED_LOADED


func unlock(stack: Yard.Stack) -> void:
	stack.containers.append(carried_id)
	carried_id = ""
	hoist.max_speed = HOIST_SPEED_EMPTY


# --- Consultas --------------------------------------------------------------

func anchor_position() -> Vector3:
	return Vector3(gantry.position, TROLLEY_ANCHOR_Y, trolley.position)


## Distancia del punto de enganche a la parte más baja de la carga.
func bottom_offset() -> float:
	return SPREADER_HEIGHT + (Yard.CONTAINER_HEIGHT if carried_id != "" else 0.0)


func spreader_bottom() -> float:
	return payload.position.y - SPREADER_HEIGHT


func load_bottom() -> float:
	return payload.position.y - bottom_offset()


## Distancia libre entre la carga y lo que tiene justo debajo.
func clearance() -> float:
	return load_bottom() - yard.surface_height(_area(payload.position))


## Cable desenrollado que no está tenso (0 si el cable está tirante).
func slack() -> float:
	return maxf(hoist.position - payload.position.distance_to(anchor_position()), 0.0)


## Ángulo del cable respecto a la vertical, en grados.
func sway_angle() -> float:
	var rope := payload.position - anchor_position()
	var length := rope.length()
	if length < 0.01 or resting:
		return 0.0
	return rad_to_deg(acos(clampf(-rope.y / length, -1.0, 1.0)))


func alignment_to(stack: Yard.Stack) -> Vector2:
	return Vector2(payload.position.x - stack.position.x, payload.position.z - stack.position.y)


## Coloca la grúa en reposo con la carga colgando quieta. Para pruebas y reinicios.
func teleport(gantry_x: float, trolley_z: float, rope_length: float) -> void:
	gantry.teleport(gantry_x)
	trolley.teleport(trolley_z)
	hoist.teleport(rope_length)
	payload.place_at(anchor_position() + Vector3.DOWN * hoist.position)
	resting = false
	side_contact = false
	_accumulator = 0.0
