## MaquinaFichar — Clock-in machine that starts the workday.
extends Interactuable

# ---------------------------------------------------------------------------
# Node reference — assign in Inspector or auto-discovered at runtime
# ---------------------------------------------------------------------------
@export var sistema_tiempo: ControladorTiempo = null

func _ready() -> void:
	if sistema_tiempo == null:
		sistema_tiempo = get_tree().get_first_node_in_group("proveedor_tiempo") as ControladorTiempo
	if sistema_tiempo == null:
		push_error("MaquinaFichar: ControladorTiempo not found.")

func interactuar() -> void:
	super.interactuar()
	if sistema_tiempo == null:
		return
	if not sistema_tiempo.jornada_iniciada:
		sistema_tiempo.intentar_fichar_entrada()
