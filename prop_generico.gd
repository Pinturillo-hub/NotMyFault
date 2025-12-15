@tool
extends Node3D

# --- TU CATÁLOGO ---
# Arrastra aquí todas las escenas (.tscn) que quieras usar.
# Al ser un Array, puedes añadir 500 objetos sin tocar el código.
@export var catalogo: Array[PackedScene]

# --- EL SELECTOR ---
# Simplemente elige el número de la lista (0, 1, 2...)
# Usamos @export_range para que te salga un deslizador cómodo.
@export_range(0, 20) var indice_seleccionado: int = 0:
	set(valor):
		indice_seleccionado = valor
		_actualizar_modelo()

var _modelo_actual: Node = null

func _ready():
	_actualizar_modelo()

func _actualizar_modelo():
	# 1. Limpiar lo viejo
	if _modelo_actual:
		_modelo_actual.queue_free()
		_modelo_actual = null
	
	# 2. Validaciones de seguridad (para no crashear)
	if catalogo.is_empty(): return
	if indice_seleccionado < 0 or indice_seleccionado >= catalogo.size(): return
	
	# 3. Instanciar el nuevo
	var escena = catalogo[indice_seleccionado]
	if escena:
		_modelo_actual = escena.instantiate()
		add_child(_modelo_actual)
		
		# Truco para que se guarde en la escena al editar
		if Engine.is_editor_hint():
			_modelo_actual.owner = get_tree().edited_scene_root
