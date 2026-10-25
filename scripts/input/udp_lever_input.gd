class_name UdpLeverInput
extends RefCounted
## Palancas físicas conectadas por red (UDP).
##
## Pensado para que un microcontrolador (Arduino/ESP32) lea las palancas
## industriales y envíe su posición como JSON, unas 30 veces por segundo:
##   {"gantry": -1..1, "trolley": -1..1, "hoist": -1..1, "lock": true/false}
## Si deja de llegar información durante TIMEOUT_MS, las palancas vuelven a
## cero: un cable de red desconectado nunca deja un movimiento "pegado".

const TIMEOUT_MS := 500

var gantry := 0.0
var trolley := 0.0
var hoist := 0.0

var _socket := PacketPeerUDP.new()
var _lock_down := false
var _lock_pressed := false
var _last_packet_ms := -TIMEOUT_MS


func listen(port: int) -> Error:
	return _socket.bind(port)


func close() -> void:
	_socket.close()


## Lee todos los paquetes pendientes. Llamar una vez por paso de física.
func poll() -> void:
	while _socket.get_available_packet_count() > 0:
		var data: Variant = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY:
			continue
		gantry = clampf(float(data.get("gantry", 0.0)), -1.0, 1.0)
		trolley = clampf(float(data.get("trolley", 0.0)), -1.0, 1.0)
		hoist = clampf(float(data.get("hoist", 0.0)), -1.0, 1.0)
		var lock := bool(data.get("lock", false))
		if lock and not _lock_down:
			_lock_pressed = true
		_lock_down = lock
		_last_packet_ms = Time.get_ticks_msec()
	if not is_active():
		gantry = 0.0
		trolley = 0.0
		hoist = 0.0
		_lock_down = false


func is_active() -> bool:
	return Time.get_ticks_msec() - _last_packet_ms < TIMEOUT_MS


## Devuelve true una sola vez por cada pulsación del botón de twistlocks.
func consume_lock_press() -> bool:
	var pressed := _lock_pressed
	_lock_pressed = false
	return pressed
