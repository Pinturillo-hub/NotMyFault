## Sello — Rubber stamp that seals Documento objects on impact.
## Uses an Area3D detector that activates briefly during the strike animation.
extends ObjetoAgarrable
class_name Sello

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const SEAL_COOLDOWN_MS: int = 500

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var _detector: Area3D = $DetectorImpacto

# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------
var _ultimo_sellado_ms: int = 0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	if _detector:
		_detector.monitoring = true
		_detector.body_entered.connect(_on_body_entered)

# ---------------------------------------------------------------------------
# Overrides — toggle detector with grab state
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func intentar_coger(solicitante_id: int) -> void:
	super.intentar_coger(solicitante_id)
	if is_instance_valid(_detector):
		_detector.set_deferred("monitoring", false)

@rpc("any_peer", "call_local", "reliable")
func intentar_soltar(solicitante_id: int, impulso: Vector3, carga: float = 0.0, velocidad_final: Vector3 = Vector3.ZERO) -> void:
	super.intentar_soltar(solicitante_id, impulso, carga, velocidad_final)
	if is_instance_valid(_detector):
		_detector.set_deferred("monitoring", true)

@rpc("any_peer", "call_local")
func usar_objeto() -> void:
	super.usar_objeto()
	if not is_instance_valid(_detector):
		return
	_detector.set_deferred("monitoring", true)
	await get_tree().create_timer(0.4).timeout
	# Only close the detector if we're still held after the animation
	if id_sostenedor_1 != 0 and is_instance_valid(_detector):
		_detector.set_deferred("monitoring", false)

# ---------------------------------------------------------------------------
# Collision
# ---------------------------------------------------------------------------

func _on_body_entered(cuerpo: Node3D) -> void:
	if not multiplayer.is_server():
		return
	var now := Time.get_ticks_msec()
	if now - _ultimo_sellado_ms < SEAL_COOLDOWN_MS:
		return
	var doc := cuerpo as Documento
	if doc == null or doc.esta_sellado:
		return
	doc.marcar_como_sellado()
	_ultimo_sellado_ms = now
	if id_sostenedor_1 != 0 and is_instance_valid(_detector):
		_detector.set_deferred("monitoring", false)
