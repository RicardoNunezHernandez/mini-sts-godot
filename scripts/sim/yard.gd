class_name Yard
extends RefCounted
## Estado del muelle y del barco: pilas de contenedores y superficies de apoyo.
##
## Ejes: X a lo largo del muelle, Y hacia arriba, Z perpendicular al muelle
## (negativo hacia el mar). Las posiciones en planta se guardan como Vector2(x, z).

## Contenedor ISO de 20 pies.
const CONTAINER_LENGTH := 6.06
const CONTAINER_WIDTH := 2.44
const CONTAINER_HEIGHT := 2.59

const QUAY_Y := 0.0
const DECK_Y := 1.5
const WATER_Y := -2.0
const SEABED_Y := -6.0
## Superficies fijas en planta: Rect2(x, z, ancho en X, fondo en Z).
const QUAY_RECT := Rect2(-80.0, 0.0, 160.0, 45.0)
const HULL_RECT := Rect2(-20.0, -24.0, 40.0, 20.0)

## Las bahías (X) son las mismas en barco y muelle; así el pórtico casi no se mueve.
const BAY_X := [-9.75, -3.25, 3.25, 9.75]
const SHIP_ROW_Z := [-7.0, -9.7, -12.4, -15.1, -17.8, -20.5]
## Carriles de camiones entre los rieles de la grúa (z = 1 y z = 14).
const LANE_Z := [3.5, 7.0, 10.5]
const MAX_LANE_TIERS := 2

const PALETTE := [
	Color(0.70, 0.16, 0.12), Color(0.12, 0.33, 0.60), Color(0.15, 0.48, 0.30),
	Color(0.85, 0.55, 0.12), Color(0.55, 0.55, 0.58), Color(0.42, 0.20, 0.45),
	Color(0.10, 0.55, 0.62), Color(0.80, 0.80, 0.78),
]


class Stack:
	var id: String
	var label: String
	## Centro en planta (x, z).
	var position: Vector2
	var base_height: float
	var on_ship: bool
	## Contenedores de abajo hacia arriba.
	var containers: Array[String] = []

	func _init(p_id: String, p_label: String, p_position: Vector2, p_base_height: float, p_on_ship: bool) -> void:
		id = p_id
		label = p_label
		position = p_position
		base_height = p_base_height
		on_ship = p_on_ship

	func top_height() -> float:
		return base_height + containers.size() * Yard.CONTAINER_HEIGHT


var stacks: Array[Stack] = []
## Color de cada contenedor por identificador.
var colors: Dictionary = {}


## Crea el escenario de entrenamiento. La misma semilla produce siempre el mismo barco.
func build_default(rng_seed: int) -> void:
	stacks.clear()
	colors.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var count := 0
	for bay in BAY_X.size():
		for row in SHIP_ROW_Z.size():
			var stack := Stack.new(
				"ship_%d_%d" % [bay, row],
				"barco, bahía %d fila %d" % [bay + 1, row + 1],
				Vector2(BAY_X[bay], SHIP_ROW_Z[row]), DECK_Y, true)
			for tier in rng.randi_range(1, 3):
				count += 1
				var container_id := "C-%02d" % count
				stack.containers.append(container_id)
				colors[container_id] = PALETTE[rng.randi() % PALETTE.size()]
			stacks.append(stack)
	for lane in LANE_Z.size():
		for bay in BAY_X.size():
			stacks.append(Stack.new(
				"lane_%d_%d" % [lane, bay],
				"muelle, carril %d posición %d" % [lane + 1, bay + 1],
				Vector2(BAY_X[bay], LANE_Z[lane]), QUAY_Y, false))


## Huella en planta de un contenedor (o del spreader) centrado en (x, z).
static func footprint(x: float, z: float) -> Rect2:
	return Rect2(x - CONTAINER_LENGTH * 0.5, z - CONTAINER_WIDTH * 0.5, CONTAINER_LENGTH, CONTAINER_WIDTH)


## Altura de la superficie más alta que toca el área dada (suelo, cubierta o contenedores).
func surface_height(area: Rect2) -> float:
	var height := SEABED_Y
	if area.intersects(QUAY_RECT):
		height = maxf(height, QUAY_Y)
	if area.intersects(HULL_RECT):
		height = maxf(height, DECK_Y)
	for stack in stacks:
		if not stack.containers.is_empty() and area.intersects(footprint(stack.position.x, stack.position.y)):
			height = maxf(height, stack.top_height())
	return height


## Pila más cercana a (x, z) dentro de las tolerancias, o null.
func stack_near(x: float, z: float, tolerance_x: float, tolerance_z: float) -> Stack:
	var best: Stack = null
	var best_distance := INF
	for stack in stacks:
		var dx := absf(x - stack.position.x)
		var dz := absf(z - stack.position.y)
		if dx <= tolerance_x and dz <= tolerance_z and dx + dz < best_distance:
			best = stack
			best_distance = dx + dz
	return best


func stack_of(container_id: String) -> Stack:
	for stack in stacks:
		if container_id in stack.containers:
			return stack
	return null
