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
	if not multiplayer.peer_connected.is_connected(_spawn_player):
		multiplayer.peer_connected.connect(_spawn_player)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
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
	# Only the server owns the player list. Clients receive it through the
	# MultiplayerSpawner; spawning locally would duplicate node names.
	if not multiplayer.is_server():
		return

	var container := get_tree().current_scene.find_child("Jugadores", true, false)
	if container == null:
		push_error("MenuPrincipal: 'Jugadores' node not found in scene.")
		return
	if container.has_node(str(player_id)):
		return

	var player := jugador_escena.instantiate()
	player.name = str(player_id)
	container.add_child(player)

	# Start game once at least 1 player is in (host-only prototype; extend for lobby)
	var ids: Array[int] = []
	for p in get_tree().get_nodes_in_group("jugadores"):
		ids.append(p.name.to_int())
	GameManager.start_game(ids)

func _on_peer_disconnected(player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var container := get_tree().current_scene.find_child("Jugadores", true, false)
	if container == null:
		return
	var player := container.get_node_or_null(str(player_id))
	if player != null:
		player.queue_free()
