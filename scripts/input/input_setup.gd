class_name InputSetup
extends RefCounted
## Registra las acciones de teclado y mando al arrancar.
##
## Se definen en código y no en Proyecto > Configuración > Mapa de entrada para
## que todo el esquema de control quede en un solo archivo legible.

const DEADZONE := 0.15


static func register_actions() -> void:
	_action("gantry_left", [KEY_A], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("gantry_right", [KEY_D], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("trolley_sea", [KEY_W], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("trolley_land", [KEY_S], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("hoist_up", [KEY_UP], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_action("hoist_down", [KEY_DOWN], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_action("precision", [KEY_SHIFT], [], [JOY_BUTTON_LEFT_SHOULDER])
	_action("lock_toggle", [KEY_SPACE], [], [JOY_BUTTON_A])
	_action("camera_next", [KEY_C], [], [JOY_BUTTON_Y])
	_action("restart", [KEY_F5], [], [JOY_BUTTON_START])
	_action("help_toggle", [KEY_H, KEY_F1], [], [JOY_BUTTON_BACK])


static func _action(action: StringName, keys: Array, axes: Array, buttons: Array = []) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, DEADZONE)
	for key: Key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
	for axis: Array in axes:
		var motion := InputEventJoypadMotion.new()
		motion.axis = axis[0]
		motion.axis_value = axis[1]
		InputMap.action_add_event(action, motion)
	for button: JoyButton in buttons:
		var press := InputEventJoypadButton.new()
		press.button_index = button
		InputMap.action_add_event(action, press)
