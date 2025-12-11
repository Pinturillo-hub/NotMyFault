extends ObjetoAgarrable

@onready var detector: Area3D = $DetectorImpacto

const COOLDOWN_MS: int = 500 
var _ultimo_tiempo_sellado: int = 0

func _ready():
	super._ready()
	if detector:
		detector.monitoring = true
		detector.body_entered.connect(_on_contacto)

@rpc("any_peer", "call_local", "reliable")
func intentar_coger(solicitante_id: int) -> void:
	super.intentar_coger(solicitante_id)
	if detector:
		# FIX: Usamos set_deferred para evitar errores de física
		detector.set_deferred("monitoring", false)

@rpc("any_peer", "call_local", "reliable")
func intentar_soltar(solicitante_id: int, impulso: Vector3) -> void:
	super.intentar_soltar(solicitante_id, impulso)
	if detector:
		detector.set_deferred("monitoring", true)

@rpc("any_peer", "call_local")
func usar_objeto():
	super.usar_objeto() 
	
	if detector:
		detector.set_deferred("monitoring", true)
		
		await get_tree().create_timer(0.4).timeout
		
		if id_sostenedor_1 != 0: 
			detector.set_deferred("monitoring", false)

func _on_contacto(cuerpo):
	if not multiplayer.is_server(): return

	var tiempo_actual = Time.get_ticks_msec()
	if tiempo_actual - _ultimo_tiempo_sellado < COOLDOWN_MS:
		return

	if cuerpo is Documento:
		if cuerpo.esta_sellado: return

		cuerpo.marcar_como_sellado()
		print("[SELLO] ¡Firmado uno!")
		
		_ultimo_tiempo_sellado = tiempo_actual
		
		if id_sostenedor_1 != 0 and detector:
			# FIX: Aquí estaba el error crítico
			detector.set_deferred("monitoring", false)
