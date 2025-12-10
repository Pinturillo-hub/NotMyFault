extends Node3D
class_name BossManager

# --- CONFIGURACIÓN ---
@export_group("Configuración de Ira")
@export var ira_maxima: float = 100.0
@export var aumento_pasivo_por_segundo: float = 2.0 # Llenará la barra en 50s si no hay caos
@export var umbral_sospecha: float = 50.0

@onready var sync = $MultiplayerSynchronizer

# --- ESTADOS ---
enum Estado { TRABAJANDO, SOSPECHANDO, INSPECCIONANDO, FIN_PARTIDA }

# Variables Sincronizadas (Añádelas al MultiplayerSynchronizer)
@export var estado_actual: Estado = Estado.TRABAJANDO
@export var ira_actual: float = 0.0

# Flags internas
var _inspeccionando_activamente: bool = false

func _ready() -> void:
	# Solo el servidor procesa la lógica
	set_process(multiplayer.is_server())

func _process(delta: float) -> void:
	if estado_actual == Estado.FIN_PARTIDA or _inspeccionando_activamente:
		return

	# 1. Aumento Pasivo de Ira
	_modificar_ira(aumento_pasivo_por_segundo * delta)
	
	# 2. Máquina de Estados (Evaluación Continua)
	_evaluar_estado()

# --- LÓGICA DE CONTROL DE IRA ---

func _modificar_ira(cantidad: float) -> void:
	ira_actual = clamp(ira_actual + cantidad, 0.0, ira_maxima)

func _evaluar_estado() -> void:
	# Transición: INSPECCIONAR (100%)
	if ira_actual >= ira_maxima:
		if estado_actual != Estado.INSPECCIONANDO:
			_iniciar_inspeccion()
			
	# Transición: SOSPECHAR (50% - 99%)
	elif ira_actual >= umbral_sospecha:
		if estado_actual != Estado.SOSPECHANDO:
			_cambiar_estado_rpc.rpc(Estado.SOSPECHANDO)
			print("[JEFE] Estado: SOSPECHANDO (Ruido de fondo activado)")
			
	# Transición: TRABAJAR (0% - 49%)
	else:
		if estado_actual != Estado.TRABAJANDO:
			_cambiar_estado_rpc.rpc(Estado.TRABAJANDO)
			print("[JEFE] Estado: TRABAJANDO (Todo tranquilo)")

# --- API PÚBLICA (Para llamar desde otros scripts) ---

# Llámalo cuando un jugador falle una tarea o haga ruido
@rpc("any_peer", "call_local")
func agregar_caos(cantidad: float) -> void:
	if multiplayer.is_server():
		print("[JEFE] ¡Caos recibido! +", cantidad)
		_modificar_ira(cantidad)

# --- RUTINA DE INSPECCIÓN ---

func _iniciar_inspeccion() -> void:
	_inspeccionando_activamente = true
	_cambiar_estado_rpc.rpc(Estado.INSPECCIONANDO)
	print("[JEFE] ¡SE ACABÓ! VOY A INSPECCIONAR.")
	
	# Aquí podrías poner un timer pequeño para dar tensión antes del veredicto
	# o una animación de la puerta abriéndose.
	await get_tree().create_timer(3.0).timeout
	
	_verificar_culpables()

func _verificar_culpables() -> void:
	var partida_terminada = false
	
	# 1. BUSCAR OBJETO ROTO HUÉRFANO (En el suelo)
	var objetos_ilegales = get_tree().get_nodes_in_group("ilegal")
	
	for obj in objetos_ilegales:
		# Verifica si nadie lo tiene en la mano Y nadie lo tiene en el bolsillo
		# Asumimos que tu script objeto_agarrable.gd tiene estas variables públicas
		if obj.id_sostenedor_1 == 0 and obj.en_bolsillo_de_id == 0:
			print("¡DESASTRE! El Jefe encontró el objeto tirado en el suelo.")
			_game_over_global.rpc()
			partida_terminada = true
			break
	
	if partida_terminada: return

	# 2. ESCANEAR JUGADORES
	var jugadores = get_tree().get_nodes_in_group("jugadores")
	for jugador in jugadores:
		if jugador.has_method("tiene_objeto_ilegal") and jugador.tiene_objeto_ilegal():
			print("¡JEFE PILLÓ AL JUGADOR ", jugador.name, "!")
			_despedir_jugador.rpc(jugador.name)
			partida_terminada = true # Opcional: ¿Se acaba el juego o solo muere él?
			# Si solo muere él, no hagas return, sigue el bucle.
			
	# 3. RESOLUCIÓN (Si nadie fue pillado)
	if not partida_terminada:
		print("[JEFE] Hmm... falsa alarma.")
		_resetear_ira()

func _resetear_ira() -> void:
	ira_actual = 0.0
	_inspeccionando_activamente = false
	_cambiar_estado_rpc.rpc(Estado.TRABAJANDO)

# --- SINCRONIZACIÓN RPC ---

@rpc("authority", "call_local", "reliable")
func _cambiar_estado_rpc(nuevo_estado: Estado):
	estado_actual = nuevo_estado
	# Aquí puedes disparar eventos visuales/sonoros en los clientes
	# Ej: AudioManager.play_tension_music()

@rpc("authority", "call_local")
func _game_over_global():
	estado_actual = Estado.FIN_PARTIDA
	set_process(false)
	print("--- FIN DE PARTIDA: TODOS DESPEDIDOS ---")
	# Aquí mostrarías la UI de derrota

@rpc("authority", "call_local")
func _despedir_jugador(nombre_jugador: String):
	print("--- JUGADOR ", nombre_jugador, " HA SIDO DESPEDIDO ---")
	# Lógica para matar/kickear/espectador al jugador específico
