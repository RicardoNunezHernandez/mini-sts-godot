class_name MeshUtil
extends RefCounted
## Ayudas para crear geometría simple (cajas) desde código.
##
## Todo el escenario se construye con cajas: es un prototipo y así no depende
## de modelos 3D externos. Más adelante cada caja se puede reemplazar por un
## modelo hecho en Blender sin tocar la simulación.

static var _materials := {}


## Material compartido por color (reutilizarlo reduce cambios de estado en la GPU).
static func material(color: Color, emission := 0.0, unshaded := false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), emission, unshaded]
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.75
		if color.a < 1.0:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if emission > 0.0:
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = emission
		if unshaded:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials[key] = mat
	return _materials[key]


static func box(size: Vector3, color: Color, center := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = center
	return instance


## Viga (caja alargada) que une dos puntos. Útil para tirantes y cables.
static func beam(a: Vector3, b: Vector3, thickness: float, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, 1.0, thickness)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material(color)
	place_beam(instance, a, b)
	return instance


## Orienta una viga creada con beam() para que vaya de `a` a `b`.
static func place_beam(instance: Node3D, a: Vector3, b: Vector3) -> void:
	var direction := b - a
	var length := direction.length()
	if length < 0.001:
		instance.visible = false
		return
	instance.visible = true
	var y_axis := direction / length
	var x_axis := y_axis.cross(Vector3.FORWARD)
	if x_axis.length() < 0.01:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis)
	# La malla mide 1 en Y; escalar ese eje por la longitud la estira entre a y b.
	instance.transform = Transform3D(Basis(x_axis, y_axis * length, z_axis), (a + b) * 0.5)
