class_name ContainersView
extends Node3D
## Dibuja los contenedores según el estado de Yard y marca el objetivo de la tarea.

const PICK_MARKER_COLOR := Color(1.0, 0.85, 0.15, 0.45)
const DROP_MARKER_COLOR := Color(0.25, 1.0, 0.45, 0.45)
const MARKER_HEIGHT := 14.0

var _nodes := {}
var _marker: MeshInstance3D
var _marker_pad: MeshInstance3D
var _box_mesh: BoxMesh


func setup(yard: Yard) -> void:
	for child in get_children():
		child.queue_free()
	_nodes.clear()
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3(Yard.CONTAINER_LENGTH, Yard.CONTAINER_HEIGHT, Yard.CONTAINER_WIDTH)
	for stack in yard.stacks:
		for container_id in stack.containers:
			_nodes[container_id] = _create_container(container_id, yard.colors[container_id])

	# Columna de luz que indica dónde trabajar.
	var column := CylinderMesh.new()
	column.top_radius = 0.5
	column.bottom_radius = 0.5
	column.height = MARKER_HEIGHT
	_marker = MeshInstance3D.new()
	_marker.mesh = column
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)
	_marker_pad = MeshUtil.box(Vector3(Yard.CONTAINER_LENGTH + 0.4, 0.06, Yard.CONTAINER_WIDTH + 0.4), DROP_MARKER_COLOR)
	_marker_pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker_pad)


func _create_container(container_id: String, color: Color) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = _box_mesh
	body.material_override = MeshUtil.material(color)
	root.add_child(body)
	# Identificador pintado en el techo (visible desde la cabina) y en un costado.
	var top_label := Label3D.new()
	top_label.text = container_id
	top_label.font_size = 96
	top_label.pixel_size = 0.012
	top_label.outline_size = 12
	top_label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	top_label.position = Vector3(0.0, Yard.CONTAINER_HEIGHT * 0.5 + 0.02, 0.0)
	root.add_child(top_label)
	var side_label := top_label.duplicate() as Label3D
	side_label.rotation_degrees = Vector3.ZERO
	side_label.position = Vector3(0.0, 0.2, Yard.CONTAINER_WIDTH * 0.5 + 0.02)
	root.add_child(side_label)
	add_child(root)
	return root


func sync(game: CraneGame, time: float) -> void:
	var yard := game.yard
	var half_height := Yard.CONTAINER_HEIGHT * 0.5
	for stack in yard.stacks:
		for tier in stack.containers.size():
			var node: Node3D = _nodes[stack.containers[tier]]
			node.position = Vector3(stack.position.x, stack.base_height + Yard.CONTAINER_HEIGHT * tier + half_height, stack.position.y)
	var model := game.model
	if model.carried_id != "":
		var carried: Node3D = _nodes[model.carried_id]
		carried.position = model.payload.position + Vector3.DOWN * (CraneModel.SPREADER_HEIGHT + half_height)

	var goal := game.current_goal()
	_marker.visible = goal != null
	_marker_pad.visible = goal != null and game.phase == CraneGame.Phase.DELIVER
	if goal == null:
		return
	var color := PICK_MARKER_COLOR if game.phase == CraneGame.Phase.PICK else DROP_MARKER_COLOR
	# Pulso suave para que la columna llame la atención sin molestar.
	color.a *= 0.75 + 0.25 * sin(time * 4.0)
	_marker.material_override = MeshUtil.material(Color(color, snappedf(color.a, 0.05)), 1.5, true)
	# En ambas fases el objetivo está en la cima de la pila: el contenedor a recoger o el hueco de destino.
	var top := goal.top_height()
	_marker.position = Vector3(goal.position.x, top + MARKER_HEIGHT * 0.5, goal.position.y)
	_marker_pad.position = Vector3(goal.position.x, top + 0.03, goal.position.y)
