extends CanvasLayer

var peer = ENetMultiplayerPeer.new()
# Asegúrate de que la ruta sea la correcta (res://entities/player/jugador.tscn)
@export var jugador_escena: PackedScene 

func _on_boton_host_pressed():
	peer.create_server(135)
	multiplayer.multiplayer_peer = peer
	visible = false
	_spawnear_jugador(1)
	multiplayer.peer_connected.connect(_spawnear_jugador)

func _on_boton_join_pressed():
	peer.create_client("127.0.0.1", 135)
	multiplayer.multiplayer_peer = peer
	visible = false

func _spawnear_jugador(id_jugador):
	var nuevo_jugador = jugador_escena.instantiate()
	nuevo_jugador.name = str(id_jugador) # ¡VITAL!
	
	# Búsqueda robusta del nodo contenedor
	var contenedor = get_tree().current_scene.find_child("Jugadores", true, false)
	if contenedor:
		contenedor.add_child(nuevo_jugador)
	else:
		print("ERROR CRÍTICO: No existe el nodo 'Jugadores' en la escena.")
