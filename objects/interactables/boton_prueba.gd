extends Interactuable

@onready var mesh: MeshInstance3D = $MeshInstance3D

func interactuar() -> void:
	# 1. GENERAMOS EL COLOR AQUÍ (Solo lo hace quien pulsó el botón)
	var color_elegido = Color(randf(), randf(), randf())
	
	# 2. ENVIAMOS ESE COLOR EXACTO A TODOS (Pasamos el dato en el paréntesis)
	rpc("aplicar_color_sincronizado", color_elegido)

# @rpc("any_peer") significa que cualquiera puede ordenar el cambio
# @rpc("call_local") significa que también se ejecuta en mi propia máquina
@rpc("any_peer", "call_local")
func aplicar_color_sincronizado(color_recibido: Color) -> void:
	print("Cambiando color a: ", color_recibido)
	
	# Aseguramos que el material sea único para no cambiar todos los objetos a la vez
	if mesh.material_override == null:
		mesh.material_override = StandardMaterial3D.new()
		
	mesh.material_override.albedo_color = color_recibido
	
	# Animación visual (Tween)
	var tween = create_tween()
	tween.tween_property(mesh, "scale", Vector3(1.2, 1.2, 1.2), 0.1)
	tween.tween_property(mesh, "scale", Vector3(1.0, 1.0, 1.0), 0.1)
