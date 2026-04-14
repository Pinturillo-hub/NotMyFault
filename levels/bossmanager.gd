## BossManager — Controls the Boss NPC threat system.
##
## Server-authoritative. Clients receive state changes via MultiplayerSynchronizer.
## Anger builds passively and from chaos events. At max anger the Boss inspects.
## Delegates win/loss resolution to GameManager.
extends Node3D
class_name BossManager

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export_group("Anger Settings")
@export var ira_maxima:             float = 100.0
@export var aumento_pasivo_por_segundo: float = 2.0
@export var umbral_sospecha:        float = 50.0
@export var chaos_per_failed_task:  float = 10.0

# ---------------------------------------------------------------------------
# Synchronized state
# ---------------------------------------------------------------------------
## Current boss anger level [0, ira_maxima]
@export var ira_actual:    float  = 0.0
## Boss behavioural state, visible to all clients for audio/visual feedback
@export var estado_actual: int    = BossState.WORKING

# ---------------------------------------------------------------------------
# Enum (int so it syncs cleanly over network)
# ---------------------------------------------------------------------------
enum BossState { WORKING, SUSPICIOUS, INSPECTING }

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal anger_changed(new_value: float, max_value: float)
signal state_changed(new_state: BossState)

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------
var _inspeccion_en_progreso: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("boss_manager")
	# Only the server runs the anger accumulation loop
	set_process(multiplayer.is_server())

func _process(delta: float) -> void:
	if estado_actual == BossState.INSPECTING:
		return  # GameManager drives inspection; we pause passive anger

	_modify_anger(aumento_pasivo_por_segundo * delta)
	_evaluate_state_transition()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Add or remove anger. Positive = more angry. Negative = calm down.
## Can be called from any peer; only the server acts on it.
@rpc("any_peer", "call_local")
func agregar_caos(cantidad: float) -> void:
	if not multiplayer.is_server():
		return
	_modify_anger(cantidad)

## Called by GameManager after a false alarm resolves.
func reset_after_false_alarm() -> void:
	ira_actual = 0.0
	_inspeccion_en_progreso = false
	_set_state(BossState.WORKING)

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _modify_anger(delta_anger: float) -> void:
	ira_actual = clamp(ira_actual + delta_anger, 0.0, ira_maxima)
	anger_changed.emit(ira_actual, ira_maxima)

func _evaluate_state_transition() -> void:
	if ira_actual >= ira_maxima:
		if not _inspeccion_en_progreso:
			_inspeccion_en_progreso = true
			_set_state(BossState.INSPECTING)
			GameManager.trigger_boss_inspection()
	elif ira_actual >= umbral_sospecha:
		if estado_actual != BossState.SUSPICIOUS:
			_set_state(BossState.SUSPICIOUS)
	else:
		if estado_actual != BossState.WORKING:
			_set_state(BossState.WORKING)

func _set_state(new_state: BossState) -> void:
	if estado_actual == new_state:
		return
	estado_actual = new_state
	_broadcast_state.rpc(new_state)

# ---------------------------------------------------------------------------
# RPCs
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _broadcast_state(new_state: BossState) -> void:
	estado_actual = new_state
	state_changed.emit(new_state)
