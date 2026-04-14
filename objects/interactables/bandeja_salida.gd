## BandejaSalida — Document validation tray (out-tray).
## Accepts sealed documents and rewards the team by reducing Boss anger.
## Rejects unsigned documents with a physical impulse.
extends StaticBody3D
class_name BandejaSalida

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export var mesh_bandeja:     MeshInstance3D = null
@export var color_bandeja:    Color          = Color.RED
@export var reduccion_caos:   float          = 5.0   # anger reduction per accepted doc

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var _detector: Area3D = $DetectorSalida

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------
var _boss_manager: BossManager = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_apply_color()
	if not multiplayer.is_server():
		return
	_boss_manager = get_tree().get_first_node_in_group("boss_manager") as BossManager
	if _boss_manager == null:
		push_warning("BandejaSalida: no BossManager found in group 'boss_manager'.")
	_detector.body_entered.connect(_on_object_received)

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

func _on_object_received(cuerpo: Node3D) -> void:
	if not multiplayer.is_server():
		return
	var doc := cuerpo as Documento
	if doc == null:
		return
	if doc.esta_sellado:
		_accept_document(doc)
	else:
		_reject_document(doc)

func _accept_document(doc: Documento) -> void:
	if _boss_manager:
		_boss_manager.rpc("agregar_caos", -reduccion_caos)
	doc.queue_free()

func _reject_document(doc: Documento) -> void:
	doc.apply_central_impulse(Vector3.UP * 3.0)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _apply_color() -> void:
	if mesh_bandeja == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color_bandeja
	mesh_bandeja.set_surface_override_material(0, mat)
