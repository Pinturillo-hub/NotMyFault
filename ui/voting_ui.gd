## VotingUI — Ballot overlay, meeting countdown and provisional result banner.
##
## Lives as a CanvasLayer in the main scene (also auto-created by the phone).
## open(player_ids, voter_id) shows the ballot; the countdown stays visible even
## after the ballot is closed so it works as a discussion phase.
extends CanvasLayer

signal voto_emitido(target_id: int)

# ---------------------------------------------------------------------------
# Node references — wire these in the scene
# ---------------------------------------------------------------------------
@onready var _container: VBoxContainer = $Panel/VBoxContainer
@onready var _titulo:    Label         = $Panel/VBoxContainer/Titulo
@onready var _contador:  Label         = $Contador
@onready var _resultado: Label         = $Resultado

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("voting_ui")
	visible = false
	_contador.visible = false
	_resultado.visible = false

func _process(_delta: float) -> void:
	if not _contador.visible:
		return
	var t := maxf(GameManager.voting_time_left, 0.0)
	_contador.text = "%d" % int(ceil(t))
	# Grows and reddens as the deadline approaches.
	var frac := clampf(1.0 - t / GameManager.VOTING_DURATION, 0.0, 1.0)
	_contador.add_theme_font_size_override("font_size", int(lerpf(40.0, 130.0, frac)))
	_contador.add_theme_color_override("font_color", Color(1.0, 1.0 - frac, 1.0 - frac))

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open(player_ids: Array[int], _voter_id: int) -> void:
	# Clear previous buttons
	for child in _container.get_children():
		if child is Button:
			child.queue_free()

	_titulo.text = "🔴 TELÉFONO ROJO\n¿Quién es el Torpe?\n(Pulsa V para reabrir la papeleta)"

	for pid in player_ids:
		var btn := Button.new()
		btn.text = "Jugador %d" % pid
		btn.pressed.connect(_on_vote_pressed.bind(pid))
		_container.add_child(btn)

	# Cancel button
	var cancel := Button.new()
	cancel.text = "Cerrar papeleta (V para reabrir)"
	cancel.pressed.connect(_on_cancel)
	_container.add_child(cancel)

	# Ballot visible, result hidden, countdown running.
	_resultado.visible = false
	_contador.visible = true
	$Panel.visible = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Provisional feedback when the meeting resolves. Called on every peer.
func mostrar_resultado(texto: String) -> void:
	_contador.visible = false
	$Panel.visible = false
	_resultado.text = texto
	_resultado.visible = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

func _on_vote_pressed(target_id: int) -> void:
	voto_emitido.emit(target_id)
	_close_panel()
	# Find the red phone and forward the vote
	var telefono := get_tree().get_first_node_in_group("telefono_rojo")
	if telefono and telefono.has_method("_recibir_voto"):
		telefono._recibir_voto(target_id)

func _on_cancel() -> void:
	_close_panel()

## Public: called by GameManager when the meeting ends.
func cerrar_ui() -> void:
	visible = false
	_contador.visible = false
	_resultado.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Hides only the ballot; the countdown keeps running during the meeting.
func _close_panel() -> void:
	$Panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
