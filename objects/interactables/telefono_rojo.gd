## TelefonoRojo — Red phone interactable.
##
## Two distinct players must activate the phone within a short window to start
## the 45-second Boardroom vote. During the vote, interacting again (or pressing
## V) re-opens the ballot locally.
## The vote is stored and resolved server-side by GameManager.
##
## Usage in scene: place a StaticBody3D with this script + a MeshInstance3D child
## for the phone model. Add it to the "telefono_rojo" group (done in _ready).
extends Interactuable

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const VOTING_UI_SCENE := "res://ui/voting_ui.tscn"
const ACTIVACIONES_NECESARIAS: int = 2
const VENTANA_ACTIVACION: float = 3.0

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export var tiempo_entre_usos: float = 2.0   # Cooldown for re-opening the ballot

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------
var _en_cooldown: bool = false
var _votante_actual_id: int = -1
var _voting_ui: Node = null
var _roto: bool = false
var _activaciones: Dictionary = {}   # peer_id -> Time.get_ticks_msec()
var _timer_ventana: Timer = null
var _label_estado: Label3D = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("telefono_rojo")
	_crear_label_estado()

	_timer_ventana = Timer.new()
	_timer_ventana.one_shot = true
	_timer_ventana.wait_time = VENTANA_ACTIVACION
	_timer_ventana.timeout.connect(_on_ventana_agotada)
	add_child(_timer_ventana)

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func interactuar() -> void:
	if _roto:
		return

	match GameManager.current_phase:
		GameManager.Phase.WORKING:
			# First interaction starts the global meeting.
			if multiplayer.is_server():
				_server_request_voting()
			else:
				rpc_id(1, "_server_request_voting")
		GameManager.Phase.BOARDROOM_VOTING:
			# Players who closed the ballot can re-open it while the timer runs.
			if _en_cooldown:
				return
			abrir_ui_local(multiplayer.get_unique_id())
		_:
			return

@rpc("any_peer", "reliable")
func _server_request_voting() -> void:
	if not multiplayer.is_server():
		return
	if _roto:
		return
	if GameManager.current_phase != GameManager.Phase.WORKING:
		return

	var sender := multiplayer.get_remote_sender_id()
	var id := sender if sender != 0 else multiplayer.get_unique_id()
	if not GameManager.roles.has(id):
		return

	var ahora := Time.get_ticks_msec()
	if _activaciones.has(id):
		# Same player pressing again: refresh feedback, but never count twice.
		if ahora - int(_activaciones[id]) < 1000:
			return
		_activaciones[id] = ahora
	else:
		_activaciones[id] = ahora
		if _activaciones.size() == 1 and _timer_ventana != null:
			_timer_ventana.start()

	_rpc_set_estado.rpc(_activaciones.size())

	if _activaciones.size() >= ACTIVACIONES_NECESARIAS:
		_iniciar_reunion()

func _iniciar_reunion() -> void:
	if _timer_ventana != null:
		_timer_ventana.stop()
	_activaciones.clear()
	_rpc_set_estado.rpc(0)
	GameManager.start_voting()

func _on_ventana_agotada() -> void:
	if not multiplayer.is_server():
		return
	_activaciones.clear()
	_rpc_set_estado.rpc(0)

## Opens the ballot on this peer for the given local player.
func abrir_ui_local(voter_id: int) -> void:
	_votante_actual_id = voter_id
	var ui := _get_or_create_voting_ui()
	if ui != null:
		ui.open(_get_votable_players(), voter_id)

## Called by GameManager when the vote is inconclusive. The phone breaks for
## the rest of the match.
func romper() -> void:
	if not multiplayer.is_server():
		return
	_activaciones.clear()
	if _timer_ventana != null:
		_timer_ventana.stop()
	_rpc_set_roto.rpc()

@rpc("authority", "call_local", "reliable")
func _rpc_set_roto() -> void:
	_roto = true
	_en_cooldown = true
	_rpc_set_estado(0)
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.05, 0.05, 1.0)
		mesh.set_surface_override_material(0, mat)

# ---------------------------------------------------------------------------
# Vote forwarding
# ---------------------------------------------------------------------------

## Called by the VotingUI when the local player selects a suspect.
func _recibir_voto(target_id: int) -> void:
	var my_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_server_recibir_voto(my_id, target_id)
	else:
		rpc_id(1, "_server_recibir_voto", my_id, target_id)
	_iniciar_cooldown()

@rpc("any_peer", "reliable")
func _server_recibir_voto(voter_id: int, target_id: int) -> void:
	if not multiplayer.is_server():
		return

	# Anti-spoofing: a remote peer can only vote for itself.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != voter_id:
		return

	GameManager.submit_vote(voter_id, target_id)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _crear_label_estado() -> void:
	_label_estado = Label3D.new()
	_label_estado.position = Vector3(0.0, 0.65, 0.0)
	_label_estado.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label_estado.font_size = 48
	_label_estado.outline_size = 8
	_label_estado.modulate = Color(1.0, 0.45, 0.3, 1.0)
	_label_estado.visible = false
	add_child(_label_estado)

@rpc("authority", "call_local", "reliable")
func _rpc_set_estado(cantidad: int) -> void:
	if _label_estado == null:
		return
	if cantidad <= 0:
		_label_estado.text = ""
		_label_estado.visible = false
	else:
		_label_estado.text = "%d/%d" % [cantidad, ACTIVACIONES_NECESARIAS]
		_label_estado.visible = true

func _iniciar_cooldown() -> void:
	_en_cooldown = true
	await get_tree().create_timer(tiempo_entre_usos).timeout
	_en_cooldown = false

func _get_votable_players() -> Array[int]:
	var ids: Array[int] = []
	for p in get_tree().get_nodes_in_group("jugadores"):
		var pid := p.name.to_int()
		if pid != _votante_actual_id:
			ids.append(pid)
	return ids

func _get_or_create_voting_ui() -> Node:
	if is_instance_valid(_voting_ui):
		return _voting_ui

	var existing := get_tree().get_first_node_in_group("voting_ui")
	if existing != null:
		_voting_ui = existing
		return _voting_ui

	var scene := load(VOTING_UI_SCENE) as PackedScene
	if scene == null:
		push_warning("TelefonoRojo: no se pudo cargar %s." % VOTING_UI_SCENE)
		return null

	var ui := scene.instantiate()
	var parent := get_tree().current_scene
	if parent == null:
		parent = get_tree().root
	parent.add_child(ui)
	_voting_ui = ui
	return _voting_ui
