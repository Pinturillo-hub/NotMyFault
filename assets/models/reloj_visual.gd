## RelojVisual — 3D clock that visualises the remaining workday time.
## Drives a radial shader and a needle rotation.
extends Node3D

# ---------------------------------------------------------------------------
# Exports — assign in Inspector
# ---------------------------------------------------------------------------
@export var mesh_cara_reloj: MeshInstance3D = null
@export var pivote_agujas:   Node3D         = null

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------
var _sistema_tiempo: Node = null   # ControladorTiempo — typed as Node to avoid forward-ref issues
var _material: ShaderMaterial = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_sistema_tiempo = get_tree().get_first_node_in_group("proveedor_tiempo")
	if _sistema_tiempo == null:
		push_error("RelojVisual: no ControladorTiempo found in group 'proveedor_tiempo'.")
		set_process(false)
		return

	if mesh_cara_reloj == null:
		push_error("RelojVisual: mesh_cara_reloj not assigned.")
		set_process(false)
		return

	_setup_material()

func _setup_material() -> void:
	var mat := mesh_cara_reloj.get_active_material(0)
	if mat == null:
		push_error("RelojVisual: no material on mesh_cara_reloj.")
		set_process(false)
		return
	if not (mat is ShaderMaterial):
		push_error("RelojVisual: material is not a ShaderMaterial.")
		set_process(false)
		return
	# Duplicate if not already local-to-scene to avoid shared state across instances
	if not mat.resource_local_to_scene:
		mat = mat.duplicate()
		mesh_cara_reloj.set_surface_override_material(0, mat)
	_material = mat as ShaderMaterial

# ---------------------------------------------------------------------------
# Process
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var total  : float = _sistema_tiempo.get("duracion_jornada") if _sistema_tiempo else 0.0
	var actual : float = _sistema_tiempo.get("tiempo_restante")  if _sistema_tiempo else 0.0

	if total <= 0.0:
		return

	var progreso: float = clamp(1.0 - (actual / total), 0.0, 1.0)

	if _material:
		_material.set_shader_parameter("progreso", progreso)

	if pivote_agujas:
		pivote_agujas.rotation_degrees.z = -360.0 * progreso
