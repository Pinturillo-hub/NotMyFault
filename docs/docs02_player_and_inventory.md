Docs: Jugador, Bolsillo Ciego y Espalda (NOT MY FAULT!)
1. El Bolsillo Ciego (Blind Pocket)
El Inventario del jugador no usa ninguna UI bidimensional. Consta de 1 único slot situado en el modelo 3D (el bolsillo trasero).
1.1. Lógica de Guardado (Meter en el bolsillo)

    Se activa cuando el jugador está mirando hacia abajo (rad_to_deg(_cabeza.rotation.x) < angulo_mirar_abajo [-60º]) y pulsa soltar objeto.
    Acciones técnicas:
        Se borra la referencia en mano.gd.
        El objeto se pasa a _objeto_en_bolsillo en jugador.gd.
        El cliente informa al servidor: objeto.rpc("entrar_en_bolsillo", name.to_int()).
        El servidor congela el objeto (freeze = true), le apaga las capas de colisión, lo vuelve invisible y lo manda a las coordenadas del limbo (LIMBO_POSITION).
        Se dispara _sync_bulto.rpc(true), lo que hace visible la malla _bulto_visual en el trasero del personaje para que los demás sepan que lleva algo.

1.2. Lógica de Extracción (Revisar es Delatarse)

    Se activa mirando hacia abajo y pulsando agarrar.
    Al no haber UI, no hay forma de saber si el objeto que tienes guardado es el marrón (la caja rota) o una grapadora. Tienes que sacarlo físicamente a la mano.
    Acciones técnicas:
        Se devuelve el objeto a mano.gd.
        Se envía una petición de salida al servidor: objeto.rpc("salir_de_bolsillo", pos_salida) ANTES de intentar_coger.
        El servidor teletransporta el objeto a la mano, restaura colisiones, descongela físicas, lo hace visible y asigna la autoridad del agarre de nuevo al jugador.
        Se apaga _bulto_visual.
    Orden crítico: si solo se llama a intentar_coger, el objeto autoritativo sigue en LIMBO_POSITION (0, -200, 0) y el muelle del servidor tiene que arrastrarlo ~200 m hasta la mano; durante ese trayecto la mano puede vaciarse por el timeout de 0.5 s de Mano._update_held_object. Por eso _sacar_de_bolsillo(equipar=true) emite primero salir_de_bolsillo(pos_salida) y después intentar_coger.
    Limpieza: entrar_en_bolsillo retira las excepciones de colisión de id_sostenedor_1 e id_sostenedor_2 antes de ponerlos a 0, para que no sobreviva una excepción obsoleta entre ciclos de bolsillo.

1.3. Colocación en el suelo (Modo fantasma, tecla E)

    Mano._execute_placement() emite salir_de_bolsillo(pos_fantasma) para teletransportar y liberar físicas, y después intentar_soltar(id_local, Vector3.ZERO).
    Este segundo RPC es necesario para que el servidor ponga id_sostenedor_1 a 0, elimine la excepción de colisión y difunda el estado. Sin él, el objeto quedaba en el suelo pero seguía marcado como agarrado por el jugador.

2. Mecánicas Sociales de Espalda (Steal / Inspect)
Ambas mecánicas utilizan el mismo sistema subyacente: un RayCast o hitbox que detecta si estás detrás de otro jugador (dot > 0.0) manteniéndote a rango de colisión durante tiempo_para_cambiazo (1.5 segundos) mientras se rellena una barra circular (con RadialFill.gdshader).
Detección en dos pasos (_get_back_target):
    1. RayCast3D desde la cámara (apuntado con el ratón). Si el primer impacto es un Jugador válido, se usa.
    2. Respaldo: ShapeCast3D horizontal a la altura del pecho (esfera de radio 0.35, alcance 2.8 m, máscara 7), hijo del cuerpo del jugador y orientado solo por el yaw del cuerpo, no por el pitch de la cámara. Se crea en código (_crear_back_cast) y excluye al propio jugador y los objetos sostenidos. Solo cuenta el primer impacto, de modo que las paredes siguen bloqueando.
    Motivo: la cámara está a ~1.09 m y la cápsula del jugador mide 1.51 m con la parte superior a ~1.02 m. Un rayo horizontal desde la cámara puede pasar por encima de la cabeza del host y el Cambiazo no arrancaba; el ShapeCast a la altura del pecho lo detecta igualmente.
2.1. El Cambiazo (Steal)

    Ejecución: Tienes un objeto en la mano. Te pegas a la espalda de otro jugador y mantienes el botón de acción de esa mano.
    Condición implementada: Solo puede ejecutarlo un jugador que tenga el rol de Torpe (GameManager.get_role(name.to_int()) == Role.LIABILITY). Se comprueba en cliente (para no iniciar la barra) y de nuevo en el servidor dentro de _server_process_steal(), que además valida que el objeto pertenece al ladrón y que está a rango. Si el cliente es INOCENTE la barra no aparece; GameManager._sync_roles imprime el rol local en consola con el formato "[ROL] peer <id> = TORPE/INOCENTE" y, en builds de depuración, el jugador local muestra un Label arriba a la izquierda con "ROL: TORPE (Cambiazo disponible)" o "ROL: INOCENTE (sin Cambiazo)" (creado en _crear_label_rol, solo local y solo si OS.is_debug_build()).
    Resolución (en el Servidor):
        El servidor le quita a la víctima lo que tuviera en su _objeto_en_bolsillo y lo pasa físicamente a la mano del ladrón.
        El objeto que el ladrón tenía en su mano, entra directamente en _objeto_en_bolsillo de la víctima (encendiendo su bulto visual).

2.2. La Inspección Arriesgada (Risk/Reward)

    Ejecución (implementada): Tienes la mano vacía. Te pegas a la espalda de otro jugador y mantienes el botón de acción de esa mano (1.5s).
    Cualquier rol puede hacerlo.
    Resolución: No se roba nada. El cliente envía _server_process_inspect(id_victima, nombre_mano). El servidor valida que la mano está vacía, que sigues detrás y a rango, y solo entonces lee la propiedad pista_inspeccion del objeto guardado de la víctima y se la envía únicamente al inspector. Si no hay pista definida, devuelve un texto genérico. La pista se muestra en un Label temporal sobre el HUD local.
    Envío de la pista: el nodo Jugador del cliente NO tiene al servidor como autoridad (su autoridad es el propio cliente), así que _rpc_recibir_pista se declara con @rpc("any_peer", "call_remote", "reliable") y el receptor descarta cualquier llamada cuyo multiplayer.get_remote_sender_id() no sea 1. Con @rpc("authority") el servidor recibía "RPC '_rpc_recibir_pista' is not allowed ... from: 1".
    El Truco Social: Desde fuera, la animación de estar pegado a la espalda de alguien inspeccionando es idéntica a la animación de hacer "El Cambiazo", por lo que si te ven haciéndolo, te llamarán Torpe.