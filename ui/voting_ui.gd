## VotingUI — Voting overlay shown to the player who picks up the red phone.
##
## Add this as a CanvasLayer child in your main scene or player scene.
## Add it to the "voting_ui" group in the Inspector so TelefonoRojo can find it.
##
## Call open(player_ids, voter_id) to show it.
## Emits voto_emitido(target_id) when a button is pressed.
extends CanvasLayer

signal voto_emitido(target_id: int)

# ---------------------------------------------------------------------------
# Node references — wire these in the scene
# ---------------------------------------------------------------------------
@onready var _container: VBoxContainer = $Panel/VBoxContainer
@onready var _titulo:    Label         = $Panel/VBoxContainer/Titulo

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("voting_ui")
	visible = false

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open(player_ids: Array[int], _voter_id: int) -> void:
	# Clear previous buttons
	for child in _container.get_children():
		if child is Button:
			child.queue_free()

	_titulo.text = "🔴 TELÉFONO ROJO\n¿Quién es el Torpe?"

	for pid in player_ids:
		var btn := Button.new()
		btn.text = "Jugador %d" % pid
		btn.pressed.connect(_on_vote_pressed.bind(pid))
		_container.add_child(btn)

	# Cancel button
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.pressed.connect(_on_cancel)
	_container.add_child(cancel)

	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

func _on_vote_pressed(target_id: int) -> void:
	voto_emitido.emit(target_id)
	_close()
	# Find the red phone and forward the vote
	var telefono := get_tree().get_first_node_in_group("telefono_rojo")
	if telefono and telefono.has_method("_recibir_voto"):
		telefono._recibir_voto(target_id)

func _on_cancel() -> void:
	_close()

## Public: called by GameManager when the meeting ends or is inconclusive.
func cerrar_ui() -> void:
	_close()

func _close() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
