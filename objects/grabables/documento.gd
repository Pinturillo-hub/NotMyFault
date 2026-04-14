## Documento — A signable office document.
## Extends ObjetoAgarrable with a sealed/unsigned visual state.
extends ObjetoAgarrable
class_name Documento

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export var esta_sellado:      bool                = false
@export var material_limpio:   StandardMaterial3D  = null
@export var material_sellado:  StandardMaterial3D  = null

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var _mesh: MeshInstance3D = $MeshInstance3D

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	_refresh_visual()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Server-authoritative seal. Call only on the server.
func marcar_como_sellado() -> void:
	if esta_sellado:
		return
	_sync_seal.rpc(true)

# ---------------------------------------------------------------------------
# RPC
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync_seal(estado: bool) -> void:
	esta_sellado = estado
	_refresh_visual()

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

func _refresh_visual() -> void:
	var mesh_node := _find_mesh()
	if mesh_node == null:
		return
	if esta_sellado:
		mesh_node.set_surface_override_material(0, material_sellado)
	else:
		mesh_node.set_surface_override_material(0, material_limpio)

func _find_mesh() -> MeshInstance3D:
	if is_instance_valid(_mesh):
		return _mesh
	var found := find_children("*", "MeshInstance3D")
	if found.size() > 0:
		return found[0] as MeshInstance3D
	return null
