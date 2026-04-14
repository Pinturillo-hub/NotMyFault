## MenuPrincipal — Lobby UI: host or join a game.
extends CanvasLayer

const PORT: int = 7000

@export var jugador_escena: PackedScene = null

var _peer := ENetMultiplayerPeer.new()

func _ready() -> void:
	if jugador_escena == null:
		push_error("MenuPrincipal: jugador_escena not assigned in Inspector.")

func _on_boton_host_pressed() -> void:
	var err := _peer.create_server(PORT)
	if err != OK:
		push_error("MenuPrincipal: failed to create server on port %d (error %d)" % [PORT, err])
		return

	multiplayer.multiplayer_peer = _peer
	multiplayer.peer_connected.connect(_spawn_player)
	_spawn_player(1)   # Host spawns itself
	visible = false

func _on_boton_join_pressed() -> void:
	var err := _peer.create_client("127.0.0.1", PORT)
	if err != OK:
		push_error("MenuPrincipal: failed to connect to server (error %d)" % err)
		return
	multiplayer.multiplayer_peer = _peer
	visible = false

func _spawn_player(player_id: int) -> void:
	if jugador_escena == null:
		return
	var player      := jugador_escena.instantiate()
	player.name      = str(player_id)
	var container   := get_tree().current_scene.find_child("Jugadores", true, false)
	if container == null:
		push_error("MenuPrincipal: 'Jugadores' node not found in scene.")
		return
	container.add_child(player)

	# Start game once at least 1 player is in (host-only prototype; extend for lobby)
	if multiplayer.is_server():
		var ids: Array[int] = []
		for p in get_tree().get_nodes_in_group("jugadores"):
			ids.append(p.name.to_int())
		GameManager.start_game(ids)
