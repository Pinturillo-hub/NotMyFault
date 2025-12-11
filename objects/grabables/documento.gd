extends ObjetoAgarrable
class_name Documento

# --- SINCRONIZACIÓN ---
@export var esta_sellado: bool = false

# --- VISUALES (Opcionales, si no los pones, usará color por defecto) ---
@export var material_limpio: StandardMaterial3D
@export var material_sellado: StandardMaterial3D

# Referencia automática a la malla (asegúrate de que el documento tiene un MeshInstance3D hijo)
@onready var mesh: MeshInstance3D = $MeshInstance3D 

func _ready():
	super._ready()
	actualizar_visual()

func marcar_como_sellado():
	if esta_sellado: return
	
	esta_sellado = true
	rpc("actualizar_visual_rpc", true)
	print("[DOCUMENTO] He sido sellado. Cambiando visual...")

@rpc("call_local", "reliable")
func actualizar_visual_rpc(estado: bool):
	esta_sellado = estado
	actualizar_visual()

func actualizar_visual():
	# Si no encontramos la malla (quizás se llama diferente), buscamos el primer hijo MeshInstance3D
	if not mesh:
		var hijos = find_children("*", "MeshInstance3D")
		if hijos.size() > 0:
			mesh = hijos[0]
		else:
			printerr("[ERROR DOCUMENTO] No encuentro el nodo MeshInstance3D para cambiarle el color.")
			return

	if esta_sellado:
		if material_sellado:
			# Opción A: Usar material asignado en inspector
			mesh.set_surface_override_material(0, material_sellado)
		else:
			# Opción B (Fallback): Crear material VERDE al vuelo para debug
			var mat_temp = StandardMaterial3D.new()
			mat_temp.albedo_color = Color.GREEN
			mesh.set_surface_override_material(0, mat_temp)
			print("[DOCUMENTO] Aviso: No hay 'material_sellado' asignado. Usando color VERDE debug.")
	else:
		if material_limpio:
			mesh.set_surface_override_material(0, material_limpio)
		else:
			# Limpiar cualquier override para volver al color original del modelo
			mesh.set_surface_override_material(0, null)
