extends Node3D

enum Estado { TRABAJANDO, SOSPECHANDO, INSPECCIONANDO, FIN_PARTIDA }

@export var estado_actual: Estado = Estado.TRABAJANDO
@export var ira_jefe: float = 0.0
@export var tiempo_para_salir: float = 60.0
@export var duracion_inspeccion: float = 5.0

@onready var sync = $MultiplayerSynchronizer

func _ready():
	if multiplayer.is_server():
		_iniciar_rutina_trabajo()

func _process(_delta): # Guion bajo para evitar warning
	pass

# --- CEREBRO ---

func _iniciar_rutina_trabajo():
	if not multiplayer.is_server(): return
	_cambiar_estado.rpc(Estado.TRABAJANDO)
	var tiempo = randf_range(10.0, 30.0)
	print("[JEFE] Volveré en ", tiempo, "s")
	await get_tree().create_timer(tiempo).timeout
	_iniciar_sospecha()

func _iniciar_sospecha():
	if not multiplayer.is_server(): return
	_cambiar_estado.rpc(Estado.SOSPECHANDO)
	print("[JEFE] ¿Ruido?")
	await get_tree().create_timer(3.0).timeout
	_salir_a_inspeccionar()

func _salir_a_inspeccionar():
	if not multiplayer.is_server(): return
	_cambiar_estado.rpc(Estado.INSPECCIONANDO)
	print("[JEFE] ¡A VER!")
	
	_verificar_culpables() # La guadaña
	
	await get_tree().create_timer(duracion_inspeccion).timeout
	if estado_actual != Estado.FIN_PARTIDA:
		print("[JEFE] Hmm... vale.")
		_iniciar_rutina_trabajo()

# --- SINCRONIZACIÓN ---

@rpc("authority", "call_local", "reliable")
func _cambiar_estado(nuevo_estado):
	estado_actual = nuevo_estado
	# Aquí meteremos luces y sonidos luego

func _verificar_culpables():
	# 1. BUSCAR OBJETO ROTO HUÉRFANO (En el suelo)
	var objetos_ilegales = get_tree().get_nodes_in_group("ilegal")
	var panico_total = false
	
	for obj in objetos_ilegales:
		# Si nadie lo tiene agarrado (id_sostenedor == 0) Y no está en un bolsillo
		if obj.id_sostenedor_1 == 0 and obj._en_bolsillo_de_id == 0:
			panico_total = true
			break
	
	if panico_total:
		print("¡DESASTRE! EL JEFE ENCONTRÓ EL OBJETO EN EL SUELO.")
		_game_over_global.rpc() # Todos pierden
		return

	# 2. ESCANEAR JUGADORES (MANOS Y BOLSILLOS)
	var jugadores = get_tree().get_nodes_in_group("jugadores")
	for jugador in jugadores:
		if jugador.tiene_objeto_ilegal():
			print("¡JEFE PILLÓ AL JUGADOR ", jugador.name, "!")
			_despedir_jugador.rpc(jugador.name)

@rpc("authority", "call_local")
func _game_over_global():
	print("--- DESPIDO MASIVO: TODOS A LA CALLE ---")
	# Lógica de fin de partida

@rpc("authority", "call_local")
func _despedir_jugador(nombre):
	print("--- JUGADOR ", nombre, " DESPEDIDO ---")
	# Aquí mataríamos al jugador
