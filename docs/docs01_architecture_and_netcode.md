Docs: Arquitectura y Netcode en Godot 4 (NOT MY FAULT!)
1. El Paradigma "Server Authoritative"
El juego usa la API multijugador de alto nivel de Godot 4.

    Servidor (Host): El jugador 1 (quien crea el lobby) siempre es el servidor. Solo el servidor ejecuta la lógica real en _physics_process y _integrate_forces de objetos compartidos (ObjetoAgarrable, BossManager).
    Clientes (Peers remotos): Los clientes solo mandan sus intenciones (inputs) al servidor vía RPCs y reciben los resultados de vuelta a través de MultiplayerSynchronizer o RPCs autoritarios.

2. Reglas de Autoridad por Nodo
2.1. Nodos del Jugador (Jugador, Mano)

    Autoridad: set_multiplayer_authority(name.to_int()). Cada peer es dueño de su propio nodo de jugador.
    Lectura de Input: Se hace SOLAMENTE si is_multiplayer_authority() es true (_setup_local_player()). Si es false, se asume que es el muñeco de otro jugador por la red y no se leen teclas locales.
    Movimiento: El cliente manda su movimiento, pero la posición final se intercala. (En el prototipo actual, el movimiento usa el _integrate_forces local del cliente).
    Teletransporte forzado (Sala de Juntas): asignar global_position a un RigidBody3D activo puede ser sobrescrito por el servidor de físicas. Jugador.teleport_to() guarda el destino en _teleport_pos/_teleport_yaw y _integrate_forces() lo fija en el state.transform del paso físico (además de limpiar velocidades y fijar _rot_objetivo_y). Funciona igual para el host (llamada directa) y para los clientes (vía RPC).
    Copias remotas: en _setup_remote_player() el cuerpo se congela con freeze = true y FREEZE_MODE_KINEMATIC. Así Jolt no simula gravedad/colisiones locales sobre un cuerpo cuya transformación llega del MultiplayerSynchronizer (evita jitter). _integrate_forces() retorna de inmediato si el nodo no es la autoridad.
    Animación remota: _process() sigue activo en las copias remotas, pero solo llama a _animate_remote_player(), que calcula la velocidad visual a partir del delta de posición sincronizada. Así se ven caminar/inclinarse sin simular físicas.

2.2. Objetos Interactuables (ObjetoAgarrable)

    Autoridad: Siempre del servidor (id 1).
    Los clientes NUNCA mueven un ObjetoAgarrable en su propio código.
    Cuando un cliente quiere coger un objeto, llama a: objeto.rpc("intentar_coger", multiplayer.get_unique_id()).
    El servidor decide si puede cogerlo (no está en otro bolsillo, etc) y asigna id_sostenedor_1 = id_del_cliente.
    Actualización Continua: Mientras lo sostiene, el cliente le manda constantemente al servidor a dónde quiere que vaya el objeto (a la posición de su mano) llamando a actualizar_objetivo_agarre de forma inestable (Unreliable): objeto_agarrado.rpc("actualizar_objetivo_agarre", pos_destino, rot_destino, mi_id)
    El servidor recibe esa coordenada objetivo, aplica las fuerzas de físicas con muelles (Springs) en _integrate_forces y la posición real resultante se sincroniza a todos los clientes automáticamente.

2.3. Gestores de Partida (GameManager, BossManager, TimeManager)

    Autoridad: Servidor.
    Las variables clave (ira_actual, current_phase, tiempo_restante) están marcadas con @export y se asume que se arrastrarán dentro de un MultiplayerSynchronizer en el árbol de la escena principal para replicarse solas.
    Solo el servidor ejecuta las funciones que alteran estos estados (ej: _modify_anger(), _evaluate_end_of_day()).
    Importante: la escena se carga ANTES de que el jugador pulse Host/Join, por lo que multiplayer.is_server() devuelve true por defecto (peer ausente) en el _ready de todos los nodos. No uses ese valor en _ready para decidir quién simula. Activa siempre _process y comprueba GameManager.es_servidor_activo(), que exige un MultiplayerPeer con estado CONNECTION_CONNECTED y unique_id == 1. Esto también evita el spam de "multiplayer instance isn't currently active" tras una desconexión.
    Fase: GameManager._sync_roles() fija current_phase = Phase.WORKING también en los clientes. Sin esto, un cliente permanece en LOBBY y sus interacciones (teléfono, estaciones) se rechazan.

3. Uso estricto de RPCs
Para este proyecto, las firmas RPC se configuran así:

    De cliente a servidor: @rpc("any_peer", "call_local", "reliable") (para acciones precisas como agarrar, soltar, robar). @rpc("any_peer", "call_local", "unreliable_ordered") (para enviar la coordenada de la mano a 60 FPS).
        Ojo: Siempre que un cliente llame a una de estas funciones, dentro de la función el servidor debe verificar: if not multiplayer.is_server(): return.
    De servidor a todos los clientes: @rpc("authority", "call_local", "reliable") (para informar de un despido, cambio de fase o resultado de una disputa).
    De servidor a UN cliente concreto sobre un nodo cuya autoridad es ese cliente: NO uses "authority", porque el servidor no es la autoridad del nodo y el RPC se rechaza con "RPC ... is not allowed ... from: 1". Usa @rpc("any_peer", "call_remote", "reliable") y valida dentro del receptor que multiplayer.get_remote_sender_id() == 1. Ejemplo: _rpc_recibir_pista en entities/player/jugador.gd.
        Ojo con las llamadas locales mezcladas con RPCs: si el servidor llama directamente (Node.call) a una función @rpc dentro del contexto de otra RPC de un cliente, multiplayer.get_remote_sender_id() devuelve el id de ESE cliente, no 0, y la validación "sender == 1" la rechaza. Separa siempre una función pública local (ej: Jugador.teleport_to) del envoltorio @rpc(_rpc_teleport_to_boardroom) y llama a la local para el jugador del host.
    Caso inverso (objetos del servidor): una RPC @rpc("authority") sobre un ObjetoAgarrable (autoridad = peer 1) solo puede emitirla el servidor. Si una función @rpc("any_peer", "call_local") como usar_objeto() se ejecuta también en clientes, no llames dentro a una RPC authority desde el cliente o Godot lanzará "RPC '_activate_ghost_mode' is not allowed ... Mode is authority". Protege la emisión con if multiplayer.is_server(): y deja que el servidor la retransmita. Ejemplo: usar_objeto() en objects/grabables/objeto_agarrable.gd.

4. Spawn de Jugadores y Documentos

    Jugadores: solo el servidor los instancia (ui/menu_principal.gd) como hijos del nodo "Jugadores". El MultiplayerSpawner de levels/sandbox.tscn los replica a los clientes. El nombre del nodo es el peer id (str(player_id)). Antes de añadir, comprueba container.has_node(str(player_id)) para no duplicar; al desconectarse un peer, el servidor libera su jugador.
    Documentos: la Bandeja de Entrada usa su propio MultiplayerSpawner. Solo debe generar documentos el servidor y únicamente en Phase.WORKING. Si un cliente arranca el Timer antes de unirse (porque is_server() era true en _ready) acaba creando documentos locales que colisionan con los replicados por el servidor y provoca el error "on_spawn_receive: Condition parent->has_node(name) is true".
    Regla general: cualquier nodo que se añada bajo un spawn_path debe existir SOLO en el servidor; los clientes lo reciben por replicación y nunca lo instancian por su cuenta.

5. Peligros a Evitar (Para la IA)

    NO llames a queue_free() en un objeto físico directamente. El servidor lo hace, o se oculta y desactiva (LIMBO_POSITION).
    Nunca manipules current_phase desde un script de cliente. Llama a un RPC del GameManager.
    Nunca uses multiplayer.is_server() en _ready para arrancar Timers o bucles de simulación; usa GameManager.es_servidor_activo() dentro del bucle.
    No mezcles @rpc("authority") con nodos cuya autoridad pertenece a otro peer (jugadores de clientes).