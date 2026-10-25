class_name CameraRig
extends Node3D
## Cámaras: cabina del operador, exterior orbital y lateral.

enum Mode { CAB, ORBIT, SIDE }
const MODE_NAMES := ["Cabina del operador", "Exterior (clic derecho + arrastrar, rueda = zoom)", "Lateral"]
## Posición del ojo del operador respecto al punto de anclaje de los cables.
const CAB_EYE_OFFSET := Vector3(3.8, -1.5, 0.0)
## Mirada casi vertical, un poco hacia el centro del carro y hacia el mar.
const CAB_LOOK_DIRECTION := Vector3(-0.22, -1.0, -0.18)

var mode := Mode.ORBIT
var camera := Camera3D.new()
var _yaw := 0.45
var _pitch := 0.42
var _distance := 70.0
var _focus := Vector3.ZERO
var _has_focus := false
var _dragging := false


func _ready() -> void:
	camera.far = 1500.0
	add_child(camera)
	camera.make_current()


func next_mode() -> String:
	mode = ((mode + 1) % Mode.size()) as Mode
	return MODE_NAMES[mode]


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.ORBIT:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_RIGHT:
				_dragging = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_distance = maxf(_distance * 0.9, 15.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = minf(_distance * 1.1, 160.0)
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * 0.005
		_pitch = clampf(_pitch + motion.relative.y * 0.005, 0.05, 1.45)


func sync(model: CraneModel, delta: float) -> void:
	var spreader := model.payload.position
	# El foco sigue al spreader con suavizado para que la cámara no tiemble con el balanceo.
	if not _has_focus:
		_focus = spreader
		_has_focus = true
	_focus = _focus.lerp(spreader, 1.0 - exp(-3.0 * delta))
	match mode:
		Mode.CAB:
			camera.fov = 70.0
			# La cabina va fija al carro y mira hacia abajo: el operador ve la carga
			# balancearse respecto a su ventana, que es justo lo que debe aprender a leer.
			# Arriba en pantalla = hacia el mar, como ve el operador sentado mirando al barco.
			var eye := model.anchor_position() + CAB_EYE_OFFSET
			_place(eye, eye + CAB_LOOK_DIRECTION, Vector3.FORWARD)
		Mode.ORBIT:
			camera.fov = 55.0
			var direction := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
			_place(_focus + direction * _distance, _focus, Vector3.UP)
		Mode.SIDE:
			camera.fov = 45.0
			# Desde el lado de la proa (-X), donde no hay puente de mando que tape la vista.
			var height := maxf(_focus.y + 2.0, 6.0)
			_place(Vector3(_focus.x - 32.0, height, _focus.z), Vector3(_focus.x, _focus.y - 1.0, _focus.z), Vector3.UP)


func _place(eye: Vector3, target: Vector3, up: Vector3) -> void:
	camera.global_position = eye
	var direction := (target - eye).normalized()
	if direction.length() > 0.0 and absf(direction.dot(up)) < 0.999:
		camera.look_at(target, up)
