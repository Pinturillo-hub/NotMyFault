## TelefonoRojo — Red phone interactable.
##
## Any player can interact with it to open a voting UI.
## Only usable while the game phase is WORKING.
## The vote is submitted server-side via GameManager.submit_vote().
##
## Usage in scene: place a StaticBody3D with this script + a MeshInstance3D child
## for the phone model. Connect the "al_interactuar" signal or just let _on_interact fire.
extends Interactuable

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export var tiempo_entre_usos: float = 30.0   # Cooldown so it can't be spammed

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------
var _en_cooldown: bool = false
var _votante_actual_id: int = -1

# ---------------------------------------------------------------------------
# Override
# ---------------------------------------------------------------------------

func interactuar() -> void:
	if GameManager.current_phase != GameManager.Phase.WORKING:
		return
	if _en_cooldown:
		return

	# Only the local authority player interacts — send their peer id to the UI
	_votante_actual_id = multiplayer.get_unique_id()
	_abrir_ui_votacion.rpc_id(_votante_actual_id)

# ---------------------------------------------------------------------------
# RPC — open voting UI on the interacting client only
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _abrir_ui_votacion() -> void:
	# Find or create the voting UI overlay on this client.
	# The UI calls back to _recibir_voto() when the player selects a target.
	var ui := _get_or_create_voting_ui()
	if ui:
		ui.open(_get_votable_players(), _votante_actual_id)

# ---------------------------------------------------------------------------
## Called by the VotingUI when the player selects a suspect.
## This runs on the local client and forwards to the server.
# ---------------------------------------------------------------------------

func _recibir_voto(target_id: int) -> void:
	rpc_id(1, "_server_recibir_voto", multiplayer.get_unique_id(), target_id)
	_iniciar_cooldown()

@rpc("any_peer", "reliable")
func _server_recibir_voto(voter_id: int, target_id: int) -> void:
	if not multiplayer.is_server():
		return
	GameManager.submit_vote(voter_id, target_id)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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
	# Look for an existing VotingUI in the scene tree.
	var existing := get_tree().get_first_node_in_group("voting_ui")
	if existing:
		return existing
	# If none exists, the scene designer should have placed a VotingUI node.
	# Log a warning so it's visible during development.
	push_warning("TelefonoRojo: no 'voting_ui' group node found. Create a VotingUI scene and add it to the scene.")
	return null
