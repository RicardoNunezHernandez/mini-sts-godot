class_name Hud
extends CanvasLayer
## Interfaz en pantalla: instrumentos de la grúa, tarea actual, guía de
## alineación, mensajes y resumen final.

const LEVEL_COLORS := {
	CraneGame.Level.INFO: Color(0.85, 0.90, 1.0),
	CraneGame.Level.OK: Color(0.45, 0.95, 0.55),
	CraneGame.Level.WARNING: Color(1.0, 0.80, 0.30),
	CraneGame.Level.ERROR: Color(1.0, 0.45, 0.40),
}
const MESSAGE_SECONDS := 4.0
const HELP_TEXT := "[b]Controles[/b]\n" \
	+ "A / D  pórtico (a lo largo del muelle)\n" \
	+ "W / S  carro (W hacia el mar)\n" \
	+ "↑ / ↓  subir / bajar\n" \
	+ "Shift  movimiento fino (30 %)\n" \
	+ "Espacio  cerrar / abrir twistlocks\n" \
	+ "C  cambiar cámara    F5  reiniciar    H  ocultar ayuda\n" \
	+ "Mando: sticks + A (twistlocks), Y (cámara), LB (fino)"

var _instruments: RichTextLabel
var _task: RichTextLabel
var _message: Label
var _help: RichTextLabel
var _help_panel: PanelContainer
var _summary: RichTextLabel
var _summary_panel: PanelContainer
var _message_left := 0.0


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var instruments_panel := _panel(root, Control.PRESET_TOP_LEFT)
	_instruments = _rich_label(instruments_panel, 340.0)

	var task_panel := _panel(root, Control.PRESET_CENTER_TOP)
	_task = _rich_label(task_panel, 560.0)

	_help_panel = _panel(root, Control.PRESET_BOTTOM_LEFT)
	_help = _rich_label(_help_panel, 420.0)
	_help.text = HELP_TEXT

	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 24)
	_message.add_theme_constant_override("outline_size", 8)
	_message.add_theme_color_override("font_outline_color", Color.BLACK)
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE, 140)
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(_message)

	_summary_panel = _panel(root, Control.PRESET_CENTER)
	_summary = _rich_label(_summary_panel, 700.0)
	_summary_panel.visible = false


func _panel(parent: Control, preset: Control.LayoutPreset) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.08, 0.72)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	panel.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, 12)
	# El contenido cambia de tamaño; el panel debe crecer hacia el interior de la pantalla.
	match preset:
		Control.PRESET_CENTER_TOP:
			panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		Control.PRESET_CENTER:
			panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
			panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		Control.PRESET_BOTTOM_LEFT:
			panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return panel


func _rich_label(parent: Control, width: float) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.custom_minimum_size.x = width
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 16)
	label.add_theme_font_size_override("bold_font_size", 17)
	label.add_theme_constant_override("table_h_separation", 28)
	parent.add_child(label)
	return label


func show_message(text: String, level: CraneGame.Level) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", LEVEL_COLORS[level])
	_message_left = MESSAGE_SECONDS


func toggle_help() -> void:
	_help_panel.visible = not _help_panel.visible


func sync(game: CraneGame, camera_name: String, levers_active: bool, delta: float) -> void:
	_message_left = maxf(_message_left - delta, 0.0)
	_message.modulate.a = clampf(_message_left, 0.0, 1.0)
	_instruments.text = _instruments_text(game.model, camera_name, levers_active)
	_task.text = _task_text(game)
	_summary_panel.visible = game.phase == CraneGame.Phase.DONE
	if _summary_panel.visible:
		_summary.text = _summary_text(game)


func _instruments_text(model: CraneModel, camera_name: String, levers_active: bool) -> String:
	var sway := model.sway_angle()
	var sway_color := "#7ef28c" if sway < 1.0 else ("#ffcc4d" if sway < 3.0 else "#ff7366")
	var locks := "[color=#7ef28c]CERRADOS (%s)[/color]" % model.carried_id if model.carried_id != "" else "[color=#ff7366]ABIERTOS[/color]"
	var lines := [
		"[b]GRÚA STS[/b]   cámara: %s" % camera_name.get_slice(" (", 0),
		"Pórtico   %+5.2f m/s   x %6.1f m" % [model.gantry.velocity, model.gantry.position],
		"Carro     %+5.2f m/s   z %6.1f m" % [model.trolley.velocity, model.trolley.position],
		"Izaje     %+5.2f m/s   cable %5.1f m" % [-model.hoist.velocity, model.hoist.position],
		"Altura libre bajo la carga: %5.1f m" % maxf(model.clearance(), 0.0),
		"Balanceo: [color=%s]%4.1f°[/color]" % [sway_color, sway],
		"Twistlocks: %s" % locks,
	]
	if model.slack() > 0.05:
		lines.append("[color=#ffcc4d]Cable flojo: carga apoyada[/color]")
	if levers_active:
		lines.append("[color=#7ec8ff]Palancas físicas conectadas (UDP)[/color]")
	return "\n".join(lines)


func _task_text(game: CraneGame) -> String:
	if game.phase == CraneGame.Phase.DONE:
		return "[center][b]Ejercicio terminado[/b] · %d puntos · F5 para repetir[/center]" % game.total_score()
	var goal := game.current_goal()
	var action := "Recoge" if game.phase == CraneGame.Phase.PICK else "Deposita"
	var text := "[center][b]Tarea %d/%d[/b] · %s [b]%s[/b] en %s\n" % [
		game.job_index + 1, CraneGame.JOBS_PER_SESSION, action, game.job_container, goal.label]
	var error := game.model.alignment_to(goal)
	text += "%s   %s   ·   %s\n" % [
		_axis_hint(error.x, CraneModel.LOCK_TOLERANCE_X, "pórtico", "D", "A"),
		_axis_hint(error.y, CraneModel.LOCK_TOLERANCE_Z, "carro", "S", "W"),
		"altura sobre destino %4.1f m" % (game.model.load_bottom() - goal.top_height()),
	]
	text += "Tiempo %s · golpes %d · apoyos bruscos %d · puntos %d[/center]" % [
		_clock(game.job_time), game.model.collisions, game.model.hard_landings, game.total_score()]
	return text


## Indica qué tecla acerca la carga al objetivo en un eje, o ✓ si ya está dentro de tolerancia.
func _axis_hint(error: float, tolerance: float, axis_name: String, key_positive: String, key_negative: String) -> String:
	if absf(error) <= tolerance:
		return "[color=#7ef28c]%s ✓ (%+.2f m)[/color]" % [axis_name, error]
	var key := key_negative if error > 0.0 else key_positive
	return "[color=#ffcc4d]%s %+.2f m → %s[/color]" % [axis_name, error, key]


func _summary_text(game: CraneGame) -> String:
	var text := "[center][b]Resumen del ejercicio[/b][/center]\n\n"
	text += "[table=6]"
	for header in ["Contenedor", "Tiempo", "Golpes", "Bruscos", "Error", "Puntos"]:
		text += "[cell][b]%s  [/b][/cell]" % header
	for result in game.results:
		text += "[cell]%s[/cell][cell]%s[/cell][cell]%d[/cell][cell]%d[/cell][cell]%.2f m[/cell][cell]%d[/cell]" % [
			result.container, _clock(result.time), result.collisions, result.hard_landings, result.error, result.score]
	text += "[/table]\n\n"
	text += "[center][b]Total: %d / %d[/b]   ·   Tiempo total %s\nF5 para repetir el mismo ejercicio[/center]" % [
		game.total_score(), CraneGame.JOBS_PER_SESSION * 1000, _clock(game.total_time)]
	return text


func _clock(seconds: float) -> String:
	return "%02d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]
