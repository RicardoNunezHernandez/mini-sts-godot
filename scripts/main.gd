extends Node3D
## Escena principal: une el modelo (CraneGame) con la vista 3D, las cámaras,
## los controles y el HUD. La física y las reglas viven en scripts/sim; aquí
## sólo se leen controles y se dibuja el estado.

## Puerto donde se escuchan las palancas físicas (ver tools/simular_palancas.py).
const LEVER_PORT := 4242
## Misma semilla = mismo barco y mismas tareas: permite comparar operadores.
const EXERCISE_SEED := 2027
## Fracción de velocidad con el modo de movimiento fino.
const PRECISION_FACTOR := 0.3

var game := CraneGame.new()
var levers := UdpLeverInput.new()
var crane_view := CraneView.new()
var containers_view := ContainersView.new()
var camera_rig := CameraRig.new()
var hud := Hud.new()
var _camera_name: String = CameraRig.MODE_NAMES[CameraRig.Mode.ORBIT]
var _time := 0.0


func _ready() -> void:
	InputSetup.register_actions()
	WorldBuilder.build(self)
	add_child(crane_view)
	add_child(containers_view)
	add_child(camera_rig)
	add_child(hud)
	game.message.connect(hud.show_message)
	_start_exercise()
	if levers.listen(LEVER_PORT) != OK:
		push_warning("No se pudo abrir el puerto UDP %d; las palancas físicas no estarán disponibles." % LEVER_PORT)


func _start_exercise() -> void:
	game.start(EXERCISE_SEED)
	containers_view.setup(game.yard)


func _physics_process(delta: float) -> void:
	levers.poll()
	if levers.consume_lock_press():
		game.toggle_lock()
	var factor := PRECISION_FACTOR if Input.is_action_pressed("precision") else 1.0
	# Teclado/mando y palancas se suman: cualquiera de los dos puede mover la grúa.
	var gantry := clampf(Input.get_axis("gantry_left", "gantry_right") * factor + levers.gantry, -1.0, 1.0)
	var trolley := clampf(Input.get_axis("trolley_sea", "trolley_land") * factor + levers.trolley, -1.0, 1.0)
	var hoist := clampf(Input.get_axis("hoist_down", "hoist_up") * factor + levers.hoist, -1.0, 1.0)
	game.update(gantry, trolley, hoist, delta)


func _process(delta: float) -> void:
	_time += delta
	crane_view.sync(game.model)
	containers_view.sync(game, _time)
	camera_rig.sync(game.model, delta)
	hud.sync(game, _camera_name, levers.is_active(), delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("lock_toggle"):
		game.toggle_lock()
	elif event.is_action_pressed("camera_next"):
		_camera_name = camera_rig.next_mode()
		hud.show_message("Cámara: " + _camera_name, CraneGame.Level.INFO)
	elif event.is_action_pressed("restart"):
		_start_exercise()
	elif event.is_action_pressed("help_toggle"):
		hud.toggle_help()


func _exit_tree() -> void:
	levers.close()
