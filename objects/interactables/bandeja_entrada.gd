## BandejaEntrada — Document spawner (in-tray).
## Spawns documents in a tidy tower without physics collisions.
## Clicking the tower removes the top document.
extends StaticBody3D
class_name BandejaEntrada

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export var documento_escena:    PackedScene = null
@export var tiempo_entre_spawns: float       = 4.0
@export var maximos_documentos:  int         = 5
@export var mesh_bandeja:        MeshInstance3D = null
@export var color_bandeja:       Color       = Color.BLUE

# Height offset per document in the tower (approximate thickness of one paper)
@export var altura_por_documento: float = 0.02

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var _punto_spawn: Marker3D           = $PuntoSpawn
@onready var _timer:       Timer              = $Timer
# MultiplayerSpawner is configured in the scene but not directly used in code

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------
var _documentos_activos: Array[ObjetoAgarrable] = []

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_apply_color()
	if not multiplayer.is_server():
		return
	if documento_escena == null:
		return
	_timer.wait_time = tiempo_entre_spawns
	_timer.timeout.connect(_on_timer_spawn)
	_timer.start()

# ---------------------------------------------------------------------------
# Spawn
# ---------------------------------------------------------------------------

func _on_timer_spawn() -> void:
	# Prune freed nodes
	_documentos_activos = _documentos_activos.filter(func(n): return is_instance_valid(n))

	if _documentos_activos.size() >= maximos_documentos:
		return
	if documento_escena == null:
		return

	var doc := documento_escena.instantiate() as ObjetoAgarrable
	if doc == null:
		return

	# Freeze document so it stays in place but still has collision
	doc.freeze = true
	doc.gravity_scale = 0.0

	# Position in the tower
	var indice := _documentos_activos.size()
	doc.position = _punto_spawn.position + Vector3.UP * (indice * altura_por_documento)
	doc.rotation = Vector3.ZERO

	add_child(doc, true)
	_documentos_activos.append(doc)

	# Update tower alignment
	_update_tower()

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func interactuar() -> void:
	_take_top_document()

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input_event(_camera: Camera3D, event: InputEvent, _click_position: Vector3, _click_normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _documentos_activos.size() > 0:
			_take_top_document()

# ---------------------------------------------------------------------------
# Document management
# ---------------------------------------------------------------------------

func _take_top_document() -> void:
	if _documentos_activos.size() == 0:
		return

	# Get the top document
	var doc: ObjetoAgarrable = _documentos_activos.pop_back()
	if not is_instance_valid(doc):
		_update_tower()
		return

	# Unfreeze and enable physics
	doc.set_deferred("freeze", false)
	doc.gravity_scale = 1.0

	# Give it a small upward nudge so it appears above the tower
	doc.global_position = doc.global_position + Vector3.UP * 0.1
	doc.linear_velocity = Vector3.ZERO
	doc.angular_velocity = Vector3.ZERO

	# Update tower
	_update_tower()

func _update_tower() -> void:
	for i in _documentos_activos.size():
		var doc := _documentos_activos[i]
		if is_instance_valid(doc):
			var target_pos := _punto_spawn.position + Vector3.UP * (i * altura_por_documento)
			doc.position = target_pos
			doc.rotation = Vector3.ZERO

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _apply_color() -> void:
	if mesh_bandeja == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color_bandeja
	mesh_bandeja.set_surface_override_material(0, mat)
