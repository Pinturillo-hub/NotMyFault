extends Interactuable # <--- ¡Herencia mágica!

@export var sistema_tiempo: ControladorTiempo

func _ready() -> void:
	# Búsqueda automática si se te olvida asignarlo en el inspector
	if not sistema_tiempo:
		sistema_tiempo = get_tree().current_scene.find_child("SistemaTiempo", true, false)

# Sobrescribimos la función del padre
func interactuar() -> void:
	# 1. Llamamos a la lógica base (por si tienes señales conectadas en el padre)
	super.interactuar() 
	
	# 2. Lógica específica de fichar
	if sistema_tiempo:
		if not sistema_tiempo.jornada_iniciada:
			print("FICHANDO ENTRADA...")
			# Animación o sonido aquí
			sistema_tiempo.intentar_fichar_entrada()
		else:
			print("Ya has fichado, ¡a trabajar!")
	else:
		print("ERROR: No encuentro el SistemaTiempo")
