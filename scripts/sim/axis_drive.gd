class_name AxisDrive
extends RefCounted
## Accionamiento de un eje de la grúa (traslación del pórtico, carro o izaje).
##
## Recibe la posición de la palanca (-1..1) y la convierte en una velocidad
## objetivo. La velocidad real se acerca a ese objetivo respetando una
## aceleración máxima, igual que el variador de frecuencia de un motor real.
## Cerca de los finales de carrera reduce la velocidad para frenar a tiempo.

var min_position: float
var max_position: float
var max_speed: float
var max_acceleration: float
var position: float
var velocity := 0.0
## Aceleración del último paso (m/s²). Sirve para telemetría o para una plataforma de movimiento.
var acceleration := 0.0


func _init(p_min: float, p_max: float, p_max_speed: float, p_max_acceleration: float, p_start: float) -> void:
	min_position = p_min
	max_position = p_max
	max_speed = p_max_speed
	max_acceleration = p_max_acceleration
	position = clampf(p_start, p_min, p_max)


func step(command: float, dt: float) -> void:
	var target := clampf(command, -1.0, 1.0) * max_speed
	# Velocidad máxima que todavía permite detenerse antes de cada final de carrera: v = sqrt(2·a·d).
	var stop_up := sqrt(2.0 * max_acceleration * maxf(max_position - position, 0.0))
	var stop_down := sqrt(2.0 * max_acceleration * maxf(position - min_position, 0.0))
	target = clampf(target, -stop_down, stop_up)

	var previous_velocity := velocity
	velocity = move_toward(velocity, target, max_acceleration * dt)
	position += velocity * dt
	if position > max_position:
		position = max_position
		velocity = minf(velocity, 0.0)
	elif position < min_position:
		position = min_position
		velocity = maxf(velocity, 0.0)
	acceleration = (velocity - previous_velocity) / dt


## Freno inmediato (por ejemplo, al detectar cable flojo).
func brake() -> void:
	velocity = 0.0
	acceleration = 0.0


## Coloca el eje en una posición y en reposo. Pensado para pruebas y reinicios.
func teleport(p_position: float) -> void:
	position = clampf(p_position, min_position, max_position)
	brake()
