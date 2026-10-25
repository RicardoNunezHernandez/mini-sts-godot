class_name RopeLoad
extends RefCounted
## Carga colgada del cable: el spreader, con o sin contenedor.
##
## Se modela como una masa puntual integrada con Verlet. El cable es una
## restricción de distancia máxima: puede aflojarse (carga apoyada) pero nunca
## estirarse. Con eso el balanceo de péndulo aparece solo, sin programarlo aparte.

const GRAVITY := 9.81

## Punto donde el cable se une al spreader (centro de su cara superior).
var position := Vector3.ZERO
## Posición del paso anterior. En Verlet la velocidad está implícita en (position - previous).
var previous := Vector3.ZERO
## Pérdida de velocidad por aire y fricción del cable, en 1/s.
var damping := 0.04
var taut := true


func place_at(p_position: Vector3) -> void:
	position = p_position
	previous = p_position


func velocity(dt: float) -> Vector3:
	return (position - previous) / dt


func integrate(dt: float) -> void:
	var displacement := position - previous
	previous = position
	position += displacement * (1.0 - damping * dt) + Vector3(0.0, -GRAVITY * dt * dt, 0.0)


## Aplica el límite de longitud del cable. Devuelve true si el cable queda tenso.
func constrain_to_rope(anchor: Vector3, length: float) -> bool:
	var offset := position - anchor
	var distance := offset.length()
	taut = distance >= length - 0.001
	if distance > length and distance > 0.0:
		position = anchor + offset / distance * length
	return taut
