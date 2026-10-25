class_name CraneView
extends Node3D
## Dibujo de la grúa. Sólo copia el estado de CraneModel a los nodos 3D;
## nunca decide nada de la física.

const STEEL_COLOR := Color(0.86, 0.30, 0.13)
const TROLLEY_COLOR := Color(0.35, 0.36, 0.38)
const CAB_COLOR := Color(0.90, 0.90, 0.88)
const SPREADER_COLOR := Color(0.95, 0.75, 0.10)
const ROPE_COLOR := Color(0.12, 0.12, 0.12)
const LOCKED_COLOR := Color(0.20, 1.00, 0.30)
const UNLOCKED_COLOR := Color(1.00, 0.20, 0.15)

const LEG_X := 9.0
const TOP_Y := 40.0
const GIRDER_X := 2.4
const GIRDER_Y := 38.6
const BOOM_SEA_Z := -32.0
const BOOM_LAND_Z := 28.0
## Puntos de los 4 cables en el carro y en el spreader (simétricos).
const ROPE_OFFSET := Vector3(1.2, 0.0, 0.9)

var _gantry := Node3D.new()
var _trolley := Node3D.new()
var _spreader := Node3D.new()
var _ropes: Array[MeshInstance3D] = []
var _lock_lights: Array[MeshInstance3D] = []


func _ready() -> void:
	add_child(_gantry)
	_build_structure()
	_gantry.add_child(_trolley)
	_build_trolley()
	add_child(_spreader)
	_build_spreader()
	for i in 4:
		var rope := MeshUtil.beam(Vector3.ZERO, Vector3.UP, 0.08, ROPE_COLOR)
		add_child(rope)
		_ropes.append(rope)


func sync(model: CraneModel) -> void:
	_gantry.position.x = model.gantry.position
	_trolley.position.z = model.trolley.position
	_spreader.position = model.payload.position
	var anchor := model.anchor_position()
	var corners := [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]
	for i in 4:
		var offset: Vector3 = ROPE_OFFSET * corners[i]
		MeshUtil.place_beam(_ropes[i], anchor + offset, model.payload.position + offset)
	var lock_color := LOCKED_COLOR if model.carried_id != "" else UNLOCKED_COLOR
	for light in _lock_lights:
		light.material_override = MeshUtil.material(lock_color, 2.0)


func _build_structure() -> void:
	var leg_height := TOP_Y
	for x in [-LEG_X, LEG_X]:
		for z in [WorldBuilder.SEA_RAIL_Z, WorldBuilder.LAND_RAIL_Z]:
			_gantry.add_child(MeshUtil.box(Vector3(1.2, leg_height, 1.2), STEEL_COLOR, Vector3(x, leg_height * 0.5, z)))
			_gantry.add_child(MeshUtil.box(Vector3(2.6, 1.2, 1.8), TROLLEY_COLOR, Vector3(x, 0.6, z)))
		# Vigas laterales del portal (fuera del paso de la carga).
		var span := WorldBuilder.LAND_RAIL_Z - WorldBuilder.SEA_RAIL_Z
		var middle_z := (WorldBuilder.SEA_RAIL_Z + WorldBuilder.LAND_RAIL_Z) * 0.5
		_gantry.add_child(MeshUtil.box(Vector3(1.2, 1.4, span + 1.2), STEEL_COLOR, Vector3(x, TOP_Y, middle_z)))
		_gantry.add_child(MeshUtil.box(Vector3(1.0, 1.0, span), STEEL_COLOR, Vector3(x, 18.0, middle_z)))
	# Travesaños superiores (por encima del carro).
	for z in [WorldBuilder.SEA_RAIL_Z, WorldBuilder.LAND_RAIL_Z]:
		_gantry.add_child(MeshUtil.box(Vector3(LEG_X * 2.0 + 1.2, 1.4, 1.4), STEEL_COLOR, Vector3(0.0, TOP_Y, z)))
	# Pluma: dos vigas por las que corre el carro.
	var boom_length := BOOM_LAND_Z - BOOM_SEA_Z
	var boom_center := (BOOM_LAND_Z + BOOM_SEA_Z) * 0.5
	for x in [-GIRDER_X, GIRDER_X]:
		_gantry.add_child(MeshUtil.box(Vector3(0.8, 1.6, boom_length), STEEL_COLOR, Vector3(x, GIRDER_Y, boom_center)))
	# Marco en A y tirantes que sostienen la punta de la pluma.
	var apex := Vector3(0.0, 54.0, WorldBuilder.LAND_RAIL_Z)
	for x in [-LEG_X, LEG_X]:
		_gantry.add_child(MeshUtil.beam(Vector3(x, TOP_Y, WorldBuilder.LAND_RAIL_Z), apex, 1.0, STEEL_COLOR))
	for x in [-GIRDER_X, GIRDER_X]:
		_gantry.add_child(MeshUtil.beam(apex, Vector3(x, GIRDER_Y + 0.8, BOOM_SEA_Z + 1.0), 0.35, STEEL_COLOR))
		_gantry.add_child(MeshUtil.beam(apex, Vector3(x, GIRDER_Y + 0.8, -8.0), 0.35, STEEL_COLOR))
		_gantry.add_child(MeshUtil.beam(apex, Vector3(x, GIRDER_Y + 0.8, BOOM_LAND_Z - 1.0), 0.35, STEEL_COLOR))
	# Sala de máquinas al fondo de la pluma.
	_gantry.add_child(MeshUtil.box(Vector3(7.0, 4.0, 6.0), CAB_COLOR, Vector3(0.0, GIRDER_Y + 2.8, BOOM_LAND_Z - 4.0)))


func _build_trolley() -> void:
	var anchor_y := CraneModel.TROLLEY_ANCHOR_Y
	_trolley.add_child(MeshUtil.box(Vector3(3.6, 1.6, 4.0), TROLLEY_COLOR, Vector3(0.0, anchor_y + 0.9, 0.0)))
	# Cabina del operador colgada a un costado del carro.
	_trolley.add_child(MeshUtil.box(Vector3(2.4, 2.6, 2.6), CAB_COLOR, Vector3(3.8, anchor_y - 0.4, 0.0)))
	_trolley.add_child(MeshUtil.box(Vector3(2.45, 1.0, 2.65), Color(0.15, 0.25, 0.35), Vector3(3.8, anchor_y - 0.2, 0.0)))
	_trolley.add_child(MeshUtil.box(Vector3(1.6, 0.4, 0.6), TROLLEY_COLOR, Vector3(2.2, anchor_y + 0.8, 0.0)))


func _build_spreader() -> void:
	var length := Yard.CONTAINER_LENGTH
	var width := Yard.CONTAINER_WIDTH
	_spreader.add_child(MeshUtil.box(Vector3(length - 0.4, 0.35, 0.6), SPREADER_COLOR, Vector3(0.0, -0.42, 0.0)))
	for x in [-1.0, 1.0]:
		_spreader.add_child(MeshUtil.box(Vector3(0.4, 0.4, width), SPREADER_COLOR, Vector3(x * (length * 0.5 - 0.2), -0.4, 0.0)))
	_spreader.add_child(MeshUtil.box(Vector3(2.8, 0.45, 2.0), SPREADER_COLOR.darkened(0.2), Vector3(0.0, -0.22, 0.0)))
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var light := MeshUtil.box(Vector3(0.3, 0.18, 0.3), UNLOCKED_COLOR, Vector3(x * (length * 0.5 - 0.2), -0.1, z * (width * 0.5 - 0.15)))
			_spreader.add_child(light)
			_lock_lights.append(light)
