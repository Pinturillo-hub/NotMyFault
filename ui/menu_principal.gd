extends CanvasLayer

var peer = ENetMultiplayerPeer.new()

# --- IMPORTANTE: Arrastra jugador.tscn aquí en el Inspector ---
@export var jugador_escena: PackedScene 

# --- CORRECCIÓN DE PUERTO PARA ANDROID ---
# No uses 135. Usa puertos entre 1024 y 65535.
const PUERTO = 7000 

func _on_boton_host_pressed():
	# Usamos el puerto seguro
	var error = peer.create_server(PUERTO)
	
	if error != OK:
		print("ERROR FATAL: No se puede crear servidor en puerto " + str(PUERTO) + ". Código error: " + str(error))
		return

	multiplayer.multiplayer_peer = peer
	visible = false
	
	print("Servidor creado con éxito en puerto: " + str(PUERTO))
	
	_spawnear_jugador(1)
	multiplayer.peer_connected.connect(_spawnear_jugador)

func _on_boton_join_pressed():
	# Recuerda: Si pruebas en el mismo móvil/PC usa "127.0.0.1"
	# Si son dos dispositivos distintos, pon la IP local del Host (ej: "192.168.1.XX")
	peer.create_client("127.0.0.1", PUERTO)
	multiplayer.multiplayer_peer = peer
	visible = false

func _spawnear_jugador(id_jugador):
	# --- CORRECCIÓN DEL ERROR 'NULL VALUE' ---
	if jugador_escena == null:
		print("ERROR CRÍTICO: ¡Se te olvidó asignar 'jugador.tscn' en el Inspector del Menú!")
		return
		
	var nuevo_jugador = jugador_escena.instantiate()
	nuevo_jugador.name = str(id_jugador)
	
	var contenedor = get_tree().current_scene.find_child("Jugadores", true, false)
	if contenedor:
		contenedor.add_child(nuevo_jugador)
	else:
		print("ERROR: No encuentro el nodo 'Jugadores' en la escena.")
