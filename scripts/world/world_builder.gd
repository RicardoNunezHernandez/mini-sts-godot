class_name WorldBuilder
extends RefCounted
## Construye el escenario fijo: cielo, luz, agua, muelle, rieles, barco y
## patio de contenedores de fondo. Nada de esto participa en la física.

const QUAY_COLOR := Color(0.52, 0.53, 0.55)
const LINE_COLOR := Color(0.92, 0.88, 0.62)
const RAIL_COLOR := Color(0.25, 0.25, 0.27)
const HULL_COLOR := Color(0.13, 0.19, 0.28)
const HULL_STRIPE_COLOR := Color(0.55, 0.12, 0.10)
const BRIDGE_COLOR := Color(0.92, 0.92, 0.90)
const WATER_COLOR := Color(0.10, 0.28, 0.40)
## Rieles de la grúa (z de las patas lado mar y lado tierra).
const SEA_RAIL_Z := 1.0
const LAND_RAIL_Z := 14.0


static func build(parent: Node3D) -> void:
	_environment(parent)
	_quay(parent)
	_ship(parent)
	_background_yard(parent)


static func _environment(parent: Node3D) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.50, 0.78)
	sky_material.sky_horizon_color = Color(0.78, 0.80, 0.84)
	sky_material.ground_horizon_color = Color(0.78, 0.80, 0.84)
	sky_material.ground_bottom_color = Color(0.20, 0.25, 0.30)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.68, 0.78)
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.70, 0.74, 0.80)
	environment.fog_density = 0.0012
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	parent.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	parent.add_child(sun)


static func _quay(parent: Node3D) -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1200.0, 1200.0)
	water.mesh = plane
	water.position = Vector3(0.0, Yard.WATER_Y, 0.0)
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = WATER_COLOR
	water_material.roughness = 0.15
	water_material.metallic_specular = 0.8
	water.material_override = water_material
	parent.add_child(water)

	var quay_rect := Yard.QUAY_RECT
	var depth := 6.0
	parent.add_child(MeshUtil.box(
		Vector3(quay_rect.size.x, depth, quay_rect.size.y), QUAY_COLOR,
		Vector3(quay_rect.get_center().x, Yard.QUAY_Y - depth * 0.5, quay_rect.get_center().y)))

	for rail_z in [SEA_RAIL_Z, LAND_RAIL_Z]:
		parent.add_child(MeshUtil.box(Vector3(quay_rect.size.x, 0.15, 0.3), RAIL_COLOR, Vector3(0.0, 0.075, rail_z)))

	# Marcas en el piso de cada posición de los carriles.
	for x: float in Yard.BAY_X:
		for z: float in Yard.LANE_Z:
			_outline(parent, Yard.footprint(x, z).grow(0.25), 0.12, LINE_COLOR)


static func _outline(parent: Node3D, rect: Rect2, width: float, color: Color) -> void:
	var y := Yard.QUAY_Y + 0.01
	var center := rect.get_center()
	for side in [-1.0, 1.0]:
		parent.add_child(MeshUtil.box(Vector3(rect.size.x, 0.02, width), color,
			Vector3(center.x, y, center.y + side * rect.size.y * 0.5)))
		parent.add_child(MeshUtil.box(Vector3(width, 0.02, rect.size.y), color,
			Vector3(center.x + side * rect.size.x * 0.5, y, center.y)))


static func _ship(parent: Node3D) -> void:
	var hull := Yard.HULL_RECT
	var bottom := Yard.SEABED_Y + 1.0
	var height := Yard.DECK_Y - bottom
	parent.add_child(MeshUtil.box(Vector3(hull.size.x, height, hull.size.y), HULL_COLOR,
		Vector3(hull.get_center().x, bottom + height * 0.5, hull.get_center().y)))
	# Franja roja de la línea de flotación.
	parent.add_child(MeshUtil.box(Vector3(hull.size.x + 0.05, 0.8, hull.size.y + 0.05), HULL_STRIPE_COLOR,
		Vector3(hull.get_center().x, Yard.WATER_Y + 0.3, hull.get_center().y)))
	# Proa en punta y puente de mando a popa.
	var bow := MeshUtil.box(Vector3(14.0, height, 14.0), HULL_COLOR,
		Vector3(hull.position.x, bottom + height * 0.5, hull.get_center().y))
	bow.rotation_degrees.y = 45.0
	parent.add_child(bow)
	parent.add_child(MeshUtil.box(Vector3(5.0, 12.0, 14.0), BRIDGE_COLOR,
		Vector3(hull.end.x - 3.0, Yard.DECK_Y + 6.0, hull.get_center().y)))
	parent.add_child(MeshUtil.box(Vector3(5.1, 1.2, 14.1), Color(0.10, 0.12, 0.15),
		Vector3(hull.end.x - 3.0, Yard.DECK_Y + 10.5, hull.get_center().y)))


## Pilas decorativas a ambos lados, fuera del recorrido de la grúa (|x| > 40)
## para que nunca tapen la cámara exterior.
static func _background_yard(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for side in [-1.0, 1.0]:
		for row in 10:
			for column in 6:
				var x: float = side * (44.0 + column * (Yard.CONTAINER_LENGTH + 0.6))
				var z := 4.0 + row * (Yard.CONTAINER_WIDTH + 0.3) + floorf(row / 2.0) * 3.0
				_background_stack(parent, rng, x, z)


static func _background_stack(parent: Node3D, rng: RandomNumberGenerator, x: float, z: float) -> void:
	for tier in rng.randi_range(0, 4):
		var color: Color = Yard.PALETTE[rng.randi() % Yard.PALETTE.size()]
		parent.add_child(MeshUtil.box(
			Vector3(Yard.CONTAINER_LENGTH, Yard.CONTAINER_HEIGHT, Yard.CONTAINER_WIDTH), color,
			Vector3(x, Yard.QUAY_Y + Yard.CONTAINER_HEIGHT * (tier + 0.5), z)))
