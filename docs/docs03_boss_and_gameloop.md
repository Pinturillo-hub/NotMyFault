Docs: Bucle de Juego, Jefe y Victoria (NOT MY FAULT!)
El ciclo de partida está regido por tres Singletons (Autoloads): TimeManager, BossManager y GameManager.
1. El Reloj de la Jornada (TimeManager.gd)

    Responsable de avanzar el tiempo de la jornada simulada (09:00 a 18:00).
    duracion_jornada debe configurarse en 480.0 segundos (8 minutos reales).
    Solo avanza si GameManager.es_servidor_activo() es true. La escena se carga antes de elegir Host/Join, así que no basta con comprobar is_server() en _ready: los clientes mantienen _process activo pero el guard lo detiene.
    Al llegar a 0, llama a GameManager.trigger_end_of_day().

2. El Jefe como Amenaza (BossManager.gd)

    No es un NPC físico normal. Es un controlador de variables numéricas.
    ira_actual va de 0.0 a 100.0.
    Aumenta pasivamente (~0.3 de ira por segundo) y activamente al sufrir sabotajes (ej: agregar_caos(15.0)) o hacer tareas mal.
    Solo el servidor activo (GameManager.es_servidor_activo()) acumula ira y cambia de estado; los clientes reciben ira_actual/estado_actual por el MultiplayerSynchronizer del SistemaJefe.
    Mecánica de Escucha: Dependiendo del nivel de Ira, emite distintos audios desde un AudioStreamPlayer3D colocado detrás de la puerta de su despacho.
    Al llegar al 100%, bloquea la acumulación, entra en estado INSPECTING, reproduce la animación de la puerta abriéndose con un portazo, y dispara GameManager.trigger_boss_inspection().

3. Matriz Lógica de Final de Partida (GameManager.gd)
GameManager es el árbitro estricto de las reglas. Solo él llama a _end_game(result). Tiene que comprobar 3 situaciones posibles de final:
3.1. Si dan las 18:00 (Fin de jornada por tiempo)
Llamado por TimeManager.gd.

    Si el objeto está reparado y en su pedestal original: Gana TORPE (Crimen Perfecto).
    Si el objeto sigue roto (donde sea, oculto o no): Ganan INOCENTES (El Torpe no lo arregló a tiempo).

    Implementación: ObjetoAgarrable expone `esta_reparado: bool` (exportada y sincronizada) y
    `radio_pedestal: float`. Al hacer _ready guarda su posición inicial como pedestal original
    (`_posicion_pedestal`) y `esta_en_pedestal()` devuelve true solo si no está en mano/bolsillo y
    sigue dentro de ese radio. GameManager._evaluate_end_of_day() exige reparado + en pedestal
    para LIABILITY_REPAIRED; cualquier otro caso da INNOCENTS_SURVIVED.

3.2. Si el Jefe sale (100% de Ira)
Llamado por BossManager.gd (_run_inspection_logic). El servidor hace un barrido de los inventarios de todos los jugadores y el suelo.

    Si alguien (Inocente) lo tiene roto encima: Gana TORPE ("La Rata", inocente despedido).
    Si El Torpe lo tiene roto encima: Ganan INOCENTES (Pillado in fraganti).
    Si está roto tirado en el suelo: TODOS PIERDEN (Despido masivo).
    Si está reparado, pero lo tiene El Torpe en la mano en ese momento (no está en su pedestal) y el Jefe sale por Caos: TODOS PIERDEN (La oficina es un desastre aunque esté reparado).

    Implementación en GameManager._run_inspection_logic(): primero se evalúan los objetos rotos
    (portador = id_sostenedor_1/2 o en_bolsillo_de_id). Si el portador es Inocente -> BOSS_CAUGHT_INNOCENT;
    si es el Torpe -> BOSS_CAUGHT_LIABILITY; si nadie lo lleva -> BOSS_FOUND_OBJECT_FLOOR. Después se
    evalúan los reparados: si el Torpe lo lleva y no está en su pedestal -> BOSS_FOUND_REPAIRED_ON_LIABILITY.
    Si no hay nada incriminatorio se dispara _end_game_false_alarm() (vuelve a WORKING, Ira a 0 y el Jefe
    vuelve a WORKING).

3.3. Si se resuelve el Teléfono Rojo (Votación)
Llamado desde telefono_rojo.gd (escena objects/interactables/telefono_rojo.tscn: StaticBody3D + MeshInstance3D + CollisionShape3D, instanciada en sandbox.tscn). El teléfono NO arranca la reunión con una sola interacción: exige ACTIVACIONES_NECESARIAS = 2 jugadores distintos dentro de VENTANA_ACTIVACION = 3.0 s. El servidor guarda _activaciones (peer_id → ticks), muestra un Label3D "1/2" sobre el teléfono (RPC _rpc_set_estado, authority) y reinicia el contador con un Timer de ventana si nadie más pulsa. Al llegar a 2, llama a GameManager.start_voting().

    Sala de Juntas (teletransporte): GameManager.start_voting() guarda las transformaciones previas (_posiciones_antes_votacion) y llama a _teleportar_jugadores_a_sala_juntas(). Usa el nodo del grupo "sala_juntas" (SalaJuntas en sandbox.tscn) y su hijo PuntoCentro: reparte a los jugadores en un círculo de radio 2.2 m, ordenados por id, mirando al centro. Para el jugador del host llama a Jugador.teleport_to(); para los clientes usa el RPC @rpc("any_peer","call_remote") _rpc_teleport_to_boardroom validando sender == 1. Si la reunión es inconcluyente, _devolver_jugadores_desde_sala_juntas() los devuelve a su posición previa antes de _broadcast_vote_inconclusive; si hay veredicto, _end_game() limpia las posiciones guardadas y la partida termina en la sala.
    Reabrir la papeleta: durante Phase.BOARDROOM_VOTING, cualquier jugador puede cerrar el VotingUI y volver a abrirlo pulsando V (Jugador._input), o interactuando de nuevo con el teléfono con cooldown. El título del VotingUI lo indica. Así la reunión puede usarse como fase de discusión sin quedar bloqueado por la distancia a la oficina.

    Los votos se acumulan en el diccionario _votes (voter_id → target_id). GameManager.submit_vote() ya no termina la partida al primer voto: espera al final del temporizador o a que todos los jugadores hayan votado.
    Movimiento y contador: durante toda la reunión el movimiento está bloqueado (Jugador._process fuerza _dir_input = Vector3.ZERO si current_phase == BOARDROOM_VOTING; se puede seguir mirando). GameManager.voting_time_left decrementa en TODOS los peers (antes solo en el servidor), así el Label "Contador" del VotingUI muestra lo mismo en host y clientes: número entero que crece de ~40 a ~130 px y pasa de blanco a rojo con el tiempo.
    Auto-voto: al agotarse el temporizador, _resolve_vote() asigna a cada jugador que no votó su propio id como objetivo (el voto va contra ti mismo) antes de contar. Nota: submit_vote() sigue rechazando el auto-voto explícito; el auto-voto solo lo inyecta el servidor en la resolución.
    Feedback (provisional): _broadcast_end() y el nuevo _broadcast_resultado() llaman a VotingUI.mostrar_resultado(texto) con un cartel grande centrado. _resultado_texto(result) es el placeholder en español de cada GameResult. La reunión inconcluyente muestra "REUNIÓN INCONCLUYENTE" 2.5 s (await en _resolve_inconclusive_vote, con _voting_resolved aún true para que _process no vuelva a resolver) antes de devolver a los jugadores y romper el teléfono. Pendiente de pulir: pantallas de fin reales y arte.
    Mayoría Cualificada: se calcula el voto más repetido y se exige required = ceil(total_jugadores * 0.5). Si el objetivo más votado alcanza ese umbral:
    Si apuntan al Torpe: Ganan INOCENTES (VOTE_CORRECT).
    Si apuntan a un Inocente: Gana TORPE (VOTE_WRONG).
    Si hay empate, votos dispersos o no se alcanza el umbral: LA PARTIDA CONTINÚA. GameManager cancela la votación, vuelve a Phase.WORKING, aplica a BossManager una penalización (agregar_caos(25.0)) y el teléfono rojo queda roto para el resto de la partida (TelefonoRojo.romper(), sincronizado a todos los peers).
    Fase en clientes: GameManager._sync_roles() fija current_phase = Phase.WORKING en todos los peers al repartir roles. Así un cliente recién unido no se queda en LOBBY y puede interactuar.
    Documentos durante la partida: BandejaEntrada solo genera documentos si GameManager.es_servidor_activo() y current_phase == Phase.WORKING. Su Timer se detiene en BOARDROOM_VOTING/BOSS_INSPECTION y nunca arranca en clientes. Esto evita el error de spawn duplicado "parent->has_node(name)".