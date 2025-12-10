extends Node3D
class_name ControladorTiempo # <--- Nombre único para evitar conflictos

# --- CONFIGURACIÓN ---
@export var duracion_jornada: float = 180.0 # 3 minutos por defecto
@export var boss_manager: BossManager # Referencia al script del Jefe (opcional)

# --- ESTADO SINCRONIZADO ---
# Añade estas variables al MultiplayerSynchronizer
@export var tiempo_restante: float = 180.0
@export var jornada_iniciada: bool = false

func _ready() -> void:
	# Añadimos este nodo al grupo para que el reloj lo encuentre fácil
	add_to_group("proveedor_tiempo")
	
	if multiplayer.is_server():
		tiempo_restante = duracion_jornada
		set_process(true)
	else:
		set_process(false) # Los clientes solo leen los datos sincronizados, no calculan

func _process(delta: float) -> void:
	# El tiempo solo corre si la jornada ha empezado
	if not jornada_iniciada: return
	
	tiempo_restante -= delta
	
	if tiempo_restante <= 0.0:
		_finalizar_jornada()

# --- LÓGICA DE CONTROL ---

func intentar_fichar_entrada() -> void:
	# Solo el servidor decide si empieza
	if multiplayer.is_server():
		if not jornada_iniciada and tiempo_restante > 0:
			jornada_iniciada = true
			print("[RELOJ] ¡Jornada iniciada! A trabajar.")
			rpc("notificar_inicio_jornada")
	else:
		rpc_id(1, "servidor_fichar_entrada") # Petición al server

@rpc("any_peer", "call_local")
func servidor_fichar_entrada():
	if multiplayer.is_server():
		intentar_fichar_entrada()

@rpc("authority", "call_local")
func notificar_inicio_jornada():
	# Aquí podrías disparar un sonido global de sirena/timbre
	pass

func _finalizar_jornada() -> void:
	jornada_iniciada = false
	tiempo_restante = 0.0
	print("[RELOJ] FIN DE JORNADA. CORTE A NEGRO.")
	
	# Llamar a la victoria en el BossManager
	if boss_manager:
		if boss_manager.has_method("evaluar_fin_jornada_victoria"):
			boss_manager.rpc("evaluar_fin_jornada_victoria")
