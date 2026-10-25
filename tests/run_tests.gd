extends SceneTree
## Pruebas automáticas del modelo físico y de las reglas.
##
## Ejecutar desde la carpeta del proyecto:
##   godot --headless --import            (sólo la primera vez)
##   godot --headless -s tests/run_tests.gd

var _failures := 0
var _checks := 0


func _init() -> void:
	var tests := [
		"test_drive_respects_acceleration",
		"test_drive_stops_at_travel_limit",
		"test_pendulum_period_matches_theory",
		"test_hanging_load_stays_still",
		"test_trolley_acceleration_causes_sway",
		"test_load_cannot_go_through_floor",
		"test_slack_rope_brake",
		"test_hard_landing_is_detected",
		"test_side_collision_blocks_motion",
		"test_lock_requires_alignment",
		"test_full_job_flow",
		"test_same_seed_same_result",
		"test_udp_levers",
	]
	for test_name in tests:
		var failures_before := _failures
		call(test_name)
		print("%s %s" % ["OK   " if _failures == failures_before else "FALLO", test_name])
	print("\n%d comprobaciones, %d fallos" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("  falló: " + description)


func near(a: float, b: float, tolerance: float, description: String) -> void:
	check(absf(a - b) <= tolerance, "%s (obtenido %.4f, esperado %.4f ± %.4f)" % [description, a, b, tolerance])


func new_model() -> CraneModel:
	var yard := Yard.new()
	yard.build_default(1)
	return CraneModel.new(yard)


## Avanza la simulación `seconds` segundos con comandos constantes.
func run(model: CraneModel, seconds: float, gantry := 0.0, trolley := 0.0, hoist := 0.0) -> void:
	var frames := int(seconds * 60.0)
	for i in frames:
		model.step(gantry, trolley, hoist, 1.0 / 60.0)


# --- Accionamientos ---------------------------------------------------------

func test_drive_respects_acceleration() -> void:
	var drive := AxisDrive.new(-100.0, 100.0, 2.0, 0.5, 0.0)
	for i in 60:
		drive.step(1.0, 1.0 / 60.0)
	near(drive.velocity, 0.5, 0.01, "tras 1 s a 0.5 m/s² la velocidad es 0.5 m/s")
	for i in 600:
		drive.step(1.0, 1.0 / 60.0)
	near(drive.velocity, 2.0, 0.001, "la velocidad no pasa del máximo")


func test_drive_stops_at_travel_limit() -> void:
	var drive := AxisDrive.new(0.0, 10.0, 3.0, 0.7, 0.0)
	for i in 60 * 30:
		drive.step(1.0, 1.0 / 60.0)
		check(drive.position <= 10.0, "nunca supera el final de carrera")
	near(drive.position, 10.0, 0.01, "llega al final de carrera")
	near(drive.velocity, 0.0, 0.01, "y se detiene")


# --- Péndulo ----------------------------------------------------------------

func test_pendulum_period_matches_theory() -> void:
	var length := 20.0
	var anchor := Vector3(0.0, 30.0, 0.0)
	var load := RopeLoad.new()
	load.damping = 0.0
	var angle := deg_to_rad(3.0)
	load.place_at(anchor + Vector3(sin(angle), -cos(angle), 0.0) * length)
	var dt := CraneModel.SUBSTEP
	var time := 0.0
	var crossings: Array[float] = []
	var previous_x := load.position.x
	while crossings.size() < 5 and time < 60.0:
		load.integrate(dt)
		load.constrain_to_rope(anchor, length)
		time += dt
		if signf(load.position.x) != signf(previous_x):
			crossings.append(time)
		previous_x = load.position.x
	# Entre el primer y el quinto cruce por la vertical hay dos periodos completos.
	var measured := (crossings[4] - crossings[0]) / 2.0
	var expected := TAU * sqrt(length / RopeLoad.GRAVITY)
	near(measured, expected, expected * 0.02, "periodo del péndulo ≈ 2π·sqrt(L/g)")


func test_hanging_load_stays_still() -> void:
	var model := new_model()
	model.teleport(0.0, 8.0, 20.0)
	var start := model.payload.position
	run(model, 10.0)
	check(model.payload.position.distance_to(start) < 0.01, "sin comandos la carga no se mueve")
	near(model.sway_angle(), 0.0, 0.01, "y no se balancea")


func test_trolley_acceleration_causes_sway() -> void:
	var model := new_model()
	model.teleport(0.0, 8.0, 20.0)
	run(model, 2.0, 0.0, 1.0)
	check(model.sway_angle() > 1.0, "acelerar el carro balancea la carga (%.2f°)" % model.sway_angle())
	check(model.payload.position.z < model.trolley.position, "la carga se queda atrás respecto al carro")


# --- Contactos --------------------------------------------------------------

func test_load_cannot_go_through_floor() -> void:
	var model := new_model()
	model.teleport(0.0, 8.0, 30.0)
	run(model, 30.0, 0.0, 0.0, -1.0)
	check(model.resting, "la carga terminó apoyada en el muelle")
	near(model.load_bottom(), Yard.QUAY_Y, 0.01, "y su base está a la altura del muelle")


func test_slack_rope_brake() -> void:
	var model := new_model()
	model.teleport(0.0, 8.0, 33.0)
	run(model, 20.0, 0.0, 0.0, -0.3)
	check(model.slack() < CraneModel.SLACK_LIMIT + 0.05, "el freno limita el cable flojo (%.2f m)" % model.slack())
	run(model, 3.0, 0.0, 0.0, 1.0)
	check(not model.resting, "al subir la carga se despega")


func test_hard_landing_is_detected() -> void:
	var model := new_model()
	model.teleport(0.0, 8.0, 32.0)
	run(model, 10.0, 0.0, 0.0, -1.0)
	check(model.hard_landings == 1, "bajar a toda velocidad cuenta un apoyo brusco")
	var gentle := new_model()
	gentle.teleport(0.0, 8.0, 33.5)
	run(gentle, 30.0, 0.0, 0.0, -0.2)
	check(gentle.resting and gentle.hard_landings == 0, "bajar despacio no penaliza")


func test_side_collision_blocks_motion() -> void:
	var model := new_model()
	# Spreader vacío a 0.3 m del muelle, frente al barco; el carro avanza hacia el mar.
	model.teleport(Yard.BAY_X[1], 2.0, rope_to_quay() - 0.3)
	run(model, 6.0, 0.0, -1.0)
	check(model.collisions >= 1, "chocar contra el casco cuenta como golpe")
	check(model.payload.position.z > Yard.HULL_RECT.end.y - 0.5, "la carga no atraviesa el casco")


## Longitud de cable con la que el spreader vacío toca el muelle.
func rope_to_quay() -> float:
	return CraneModel.TROLLEY_ANCHOR_Y - CraneModel.SPREADER_HEIGHT - Yard.QUAY_Y


# --- Reglas -----------------------------------------------------------------

func test_lock_requires_alignment() -> void:
	var model := new_model()
	var stack: Yard.Stack = model.yard.stacks[0]
	var drop := CraneModel.TROLLEY_ANCHOR_Y - CraneModel.SPREADER_HEIGHT - stack.top_height()
	model.teleport(stack.position.x + 0.6, stack.position.y, drop - 0.5)
	run(model, 3.0, 0.0, 0.0, -0.2)
	check(model.find_lock_candidate() == null, "desalineado 0.6 m no se puede cerrar")
	model.teleport(stack.position.x + 0.1, stack.position.y, drop - 0.5)
	run(model, 4.0, 0.0, 0.0, -0.2)
	check(model.find_lock_candidate() == stack, "desalineado 0.1 m sí se puede cerrar")


func test_full_job_flow() -> void:
	var game := CraneGame.new()
	game.start(7)
	var source := game.current_goal()
	var container := game.job_container
	_lower_onto(game.model, source)
	check(game.toggle_lock(), "cierra twistlocks sobre el contenedor asignado")
	check(game.phase == CraneGame.Phase.DELIVER, "pasa a la fase de entrega")
	check(game.yard.stack_of(container) == null, "el contenedor ya no está en la pila de origen")
	var target := game.current_goal()
	_lower_onto(game.model, target)
	check(game.toggle_lock(), "abre twistlocks en el destino")
	check(game.yard.stack_of(container) == target, "el contenedor quedó en el destino")
	check(game.results.size() == 1 and int(game.results[0].score) > 0, "la tarea suma puntos")
	check(game.job_index == 1 and game.phase == CraneGame.Phase.PICK, "empieza la siguiente tarea")


func _lower_onto(model: CraneModel, stack: Yard.Stack) -> void:
	var drop := CraneModel.TROLLEY_ANCHOR_Y - model.bottom_offset() - stack.top_height()
	model.teleport(stack.position.x, stack.position.y, drop - 1.0)
	run(model, 8.0, 0.0, 0.0, -0.2)


func test_same_seed_same_result() -> void:
	var a := new_model()
	var b := new_model()
	for model in [a, b]:
		run(model, 4.0, 1.0, -1.0, 0.5)
		run(model, 3.0, -0.5, 0.0, -0.5)
	check(a.payload.position == b.payload.position, "misma entrada, mismo resultado (determinista)")


# --- Palancas por red -------------------------------------------------------

func test_udp_levers() -> void:
	var levers := UdpLeverInput.new()
	var port := 47420
	check(levers.listen(port) == OK, "abre el puerto UDP")
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1", port)
	sender.put_packet(JSON.stringify({"gantry": 0.5, "trolley": -2.0, "hoist": 0.25, "lock": true}).to_utf8_buffer())
	sender.put_packet("esto no es JSON".to_utf8_buffer())
	OS.delay_msec(50)
	levers.poll()
	check(levers.is_active(), "recibió datos")
	near(levers.gantry, 0.5, 0.0001, "lee la palanca del pórtico")
	near(levers.trolley, -1.0, 0.0001, "recorta valores fuera de rango")
	check(levers.consume_lock_press(), "detecta la pulsación de twistlocks")
	check(not levers.consume_lock_press(), "la pulsación se consume una sola vez")
	levers.close()
