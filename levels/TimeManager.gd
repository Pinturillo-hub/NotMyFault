## ControladorTiempo — Authoritative workday clock.
##
## The server ticks the clock. Clients receive tiempo_restante via
## MultiplayerSynchronizer. When the clock reaches zero, GameManager is
## notified to evaluate the end-of-day result.
extends Node3D
class_name ControladorTiempo

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export var duracion_jornada: float = 480.0  # seconds (8 real minutes)

# ---------------------------------------------------------------------------
# Synchronized state
# ---------------------------------------------------------------------------
@export var tiempo_restante: float = 480.0
@export var jornada_iniciada: bool = false

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal jornada_terminada

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group("proveedor_tiempo")
	tiempo_restante = duracion_jornada
	# Process stays enabled; _process checks authoritative status itself. The
	# scene loads before the host/join choice assigns the MultiplayerPeer.
	set_process(true)

func _process(delta: float) -> void:
	if not GameManager.es_servidor_activo():
		return
	if not jornada_iniciada:
		return
	tiempo_restante -= delta
	if tiempo_restante <= 0.0:
		tiempo_restante = 0.0
		jornada_iniciada = false
		set_process(false)
		_on_end_of_day()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Start the workday. Server-authoritative; clients call via RPC.
func intentar_fichar_entrada() -> void:
	if GameManager.es_servidor_activo():
		_server_start_day()
	else:
		rpc_id(1, "_rpc_request_start")

@rpc("any_peer", "reliable")
func _rpc_request_start() -> void:
	if GameManager.es_servidor_activo():
		_server_start_day()

func _server_start_day() -> void:
	if jornada_iniciada or tiempo_restante <= 0.0:
		return
	jornada_iniciada = true
	_notify_day_started.rpc()

@rpc("authority", "call_local", "reliable")
func _notify_day_started() -> void:
	pass  # Clients react to jornada_iniciada sync; hook audio/visuals here

# ---------------------------------------------------------------------------
# End of day
# ---------------------------------------------------------------------------

func _on_end_of_day() -> void:
	jornada_terminada.emit()
	GameManager.trigger_end_of_day()
