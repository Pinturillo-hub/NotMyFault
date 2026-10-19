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

    Mano._execute_placement() emite salir_de_bolsillo(pos_fantasma) para teletransportar y liberar físicas, y después intentar_soltar(id_local, Vector3.ZERO, 0.0).
    Este segundo RPC es necesario para que el servidor ponga id_sostenedor_1 a 0, elimine la excepción de colisión y difunda el estado. Sin él, el objeto quedaba en el suelo pero seguía marcado como agarrado por el jugador.
    Ojo con las referencias durante el sellado: _broadcast_state() es call_local y, al soltar, emite disputa_finalizada de forma sincrónica en el host; la mano conectada a esa señal hace limpiar_estado_local(), que pone objeto_agarrado = null. Por eso _execute_placement() guarda primero var obj := objeto_agarrado y opera siempre sobre obj (antes daba el error "Invalid assignment of property 'global_rotation' ... on a base object of type 'Nil'").

1.4. Clases de peso (objeto_agarrable.gd, CONFIG_PESO)

    No se asignan kilogramos por escena. ObjetoAgarrable expone @export var peso: Peso { LIGERO, MEDIO, PESADO } y CONFIG_PESO es la única fuente de verdad: masa física, respuesta del muelle, gravedad mientras se sostiene, ralentización del jugador, multiplicador de lanzamiento, distancia máxima de tirón, duración del tropiezo y fuerza mínima de impacto para tumbar (fuerza_tropiezo).
    Para añadir una clase: añade el valor al enum Peso y su entrada en CONFIG_PESO. Los valores se cachean en _aplicar_config_peso() (llamado en _ready y en el setter de peso).

    LIGERO (Documento, Sello, CajaRota): masa 0.8, muelle 1.0, sin ralentización, lanzamiento x1.3, tiron_max = INF, tropiezo 0.7 s, tumba a partir del 90% de carga (fuerza_tropiezo = 0.9).
    MEDIO (CajaPrueba): masa 5.0, muelle 0.6, ralentización 0.85, lanzamiento x0.6, tiron_max = INF, tropiezo 0.85 s, tumba a partir del 50% de carga (fuerza_tropiezo = 0.5).
    PESADO (Mesa2): masa 25.0, ralentización 0.5, gravedad_sostenido = 1.0, arrastre = true, lanzamiento x0.3, tiron_max = 1.2 m, tropiezo 1.0 s; tumba a partir del 70% de carga (fuerza_tropiezo = 0.7).

    Arrastre pesado: _apply_spring_forces() deriva a _apply_drag(). En vez de muelle, aplica un servo de velocidad horizontal (máx. 3.4 m/s, aceleración 10 m/s²) y deja actuar la gravedad, de modo que el objeto se arrastra por el suelo pero no se puede levantar. El giro usa un par débil (ARRASTRE_GIRO = 0.2) para que la mesa pueda girar despacio sin comportarse como una peonza.

    Tirón roto: Mano._comprobar_tiron() se ejecuta solo en el peer del portador tras 0.8 s de gracia. Mide la distancia 3D entre el punto de agarre del objeto y pos_accion; si supera tiron_max durante 0.3 s seguidos (para no romper en un giro rápido), hace intentar_soltar(id_local, ZERO, 0.0), llama a Jugador.tropezar() y limpia la mano. Con las dos manos sobre el mismo objeto, el margen se multiplica por BONUS_TIRON_DOS_MANOS (1.5).

    Tropiezo (volcar y levantarse): Jugador.tropezar(direccion, duracion) añade 3.5 m/s de lurch, bloquea el input y reduce el frenado al 15% mientras dure el tropiezo. Además lanza un Tween que vuelca el modelo (angulo_volcado, por defecto 80º) y acompaña la cámara (angulo_volcado_camara / roll_volcado), con una fracción de caída (fraccion_caida) y el resto para levantarse; al terminar, el modelo y la cámara vuelven a 0 y se reanuda el control. El tween es local (solo lo ve el jugador que cae). Al caer, _soltar_manos() suelta cualquier objeto que cualquiera de las dos manos esté sujetando. El tropiezo se dispara por el tirón roto y por impactos de objetos lanzados.

    Indicador de agarre: mientras se sostiene un objeto con tiron_max finito (los pesados), Mano._comprobar_tiron() publica tension_agarre = distancia / distancia_max (0..1). Jugador muestra una barra en la parte inferior central (ProgressBar creada en _crear_barra_tension) que se llena y pasa de verde a rojo al acercarse al límite de rotura, de modo que el jugador ve cuánto le falta para tropezar. Se oculta al soltar o para objetos que nunca se rompen.

    Impactos que tumban: con contact_monitor activo, ObjetoAgarrable._on_objeto_body_entered() detecta el choque de un objeto lanzado contra un jugador. Solo el servidor resuelve el golpe y compara la carga del lanzamiento (0..1) con fuerza_tropiezo de su clase (ligero 0.9, medio 0.5, pesado 0.7); si la alcanza, envía _rpc_tropiezo al cliente de la víctima (validando que el emisor sea el peer 1). El lanzador no puede tumbarse a sí mismo y hay un cooldown de 600 ms entre golpes del mismo objeto.

    Golpes: solo el portador tiene excepción de colisión con el objeto. El resto de jugadores recibe el impulso físico real (masa del jugador = 70 kg), por lo que el peso de la clase escala el golpe de forma natural: ligero apenas empuja, medio es moderado y pesado empuja fuerte.

    Lanzamiento: Mano.soltar() solo suelta (no lanza). El lanzamiento con velocidad objetivo vive ahora en el giro de cámara (ver 1.6): velocidad_lanzamiento / velocidad_lanzamiento_maxima (por defecto 2..5 m/s), multiplicada por factor_lanzamiento, de modo que el ligero vuela más y el pesado apenas sale de la mano.

    Bolsillo y Cambiazo: se_puede_guardar() devuelve false para PESADO. Jugador bloquea guardarlo en el bolsillo (aviso "Demasiado pesado...") y _server_process_steal() aborta el Cambiazo si el objeto del ladrón es pesado.

1.5. Agarre a dos manos (mismo jugador)

    Las dos manos pueden sujetar el mismo objeto. En el servidor, un segundo intentar_coger() del mismo solicitante pone ObjetoAgarrable.agarre_doble = true; no inicia forcejeo ni reasigna el objeto. Mientras dura, _apply_spring_forces() y _apply_drag() multiplican la fuerza por FUERZA_DOS_MANOS (1.8), de modo que una mesa pesada se arrastra más rápido y responde mejor; en Jugador._factor_carga() la ralentización se multiplica por BONUS_DOS_MANOS (1.4), con tope en 1.0.

    Para que las dos manos no peleen por el mismo objeto, Mano.mano_companera apunta a la otra mano (se enlaza en Jugador._setup_local_player). Con las dos manos sobre el mismo objeto solo la mano derecha envía actualizar_objetivo_agarre(); la izquierda actúa como secundaria y no manda objetivos. Al soltar (cualquier mano, lanzar o colocar), el objeto se libera por completo y agarre_doble vuelve a false.

1.6. Agarre débil/fuerte, lanzamiento por giro y robo desde la mano

    Dos modos de agarre con el mismo botón de mano (click izquierdo = mano derecha, click derecho = mano izquierda):
        Click corto (< tiempo_para_lanzar, 0.3 s): el objeto queda pegado a la mano. Es el "agarre débil" (ObjetoAgarrable.agarre_fuerte = false). Se lleva sin necesidad de mantener pulsado y se puede arrebatar con un click de otro jugador.
        Mantener el click: "agarre fuerte" (agarre_fuerte = true). Se envía por RPC actualizar_tipo_agarre() al primer frame con el botón pulsado, y al soltar vuelve a false. Mientras se mantiene, soltar el botón deja caer el objeto; si además la cámara venía girando, el objeto sale lanzado.

    Lanzamiento por giro de cámara (sustituye a la antigua barra de carga): Mano._actualizar_giro_y_agarre() mide la velocidad angular de la cabeza (rad/s) suavizada en _giro_actual, que se reinicia al agarrar (solo cuenta el giro durante el mantenido). Al soltar tras un mantenido, si _giro_actual >= giro_minimo (1 rad/s) el objeto se lanza en la dirección de la velocidad de la mano (si es despreciable, hacia delante de la mano) con velocidad = lerp(velocidad_lanzamiento, velocidad_lanzamiento_maxima, intensidad) x factor_lanzamiento (por defecto 2..5 m/s, poca intensidad). Por debajo del umbral solo se suelta. La velocidad del lanzamiento se IMPONE (intentar_soltar recibe velocidad_final y hace linear_velocity = velocidad_final) en lugar de sumar un impulso, para que la inercia de la mano no se apile y un giro suave salga suave. Caminar no dispara el lanzamiento (no gira la cabeza). No hay barra de carga: mientras se mantiene el click no se muestra ningún porcentaje.

    Robo desde la mano (hand steal): apuntando con el raycast al objeto que sostiene otro jugador (alcance ROBO_ALCANCE = 3.5 m, validado en intentar_coger), el servidor decide:
        Si la víctima lo lleva con agarre débil (click simple): _assign_holder(ladrón) al instante. La mano de la víctima se limpia al recibir disputa_finalizada(ganador).
        Si la víctima lo lleva con agarre fuerte (mantiene el click): _start_tug_of_war(ladrón) y empieza el forcejeo.

    Forcejeo (tug-of-war): el servidor marca en_disputa = true, id_sostenedor_2 = ladrón y pone gravity_scale = 0 al objeto. En _integrate_forces(), mientras en_disputa, el objeto no persigue a ninguna mano: solo amortigua su velocidad, de modo que queda colgado entre los dos. Cada jugador (con el click pulsado) reporta por enviar_fuerza_tiro() la distancia que ha alejado la mano del objeto este frame (arrastrando el ratón o caminando hacia atrás). El servidor acumula _tug_pull_1 / _tug_pull_2 y replica el reparto con _rpc_tug_progreso():
        Si _tug_pull_1 + _tug_pull_2 >= TUG_UMBRAL (4 m) o se agota TUG_DURACION_MAX (6 s): gana quien más tiró; _resolver_disputa() llama a _assign_holder(ganador) y _hacer_tropezar(perdedor), que envía _rpc_tropiezo al perdedor en dirección al objeto.
        Si cualquiera de los dos suelta el click durante la disputa: intentar_soltar() desvía a _abortar_disputa(): se sueltan ambos, el objeto sale disparado a TUG_ESCAPE_SPEED (7 m/s, marcado como lanzado para que pueda tumbar) y ambos jugadores tropiezan.
    Mientras _en_disputa_activa, Mano._comprobar_tiron() se salta (para que el estirón no rompa el agarre) y el jugador no puede usar ni lanzar el objeto; soltar el botón aborta.

    UI de potencia de agarre: Jugador._crear_barra_disputa() crea un indicador central (solo local) que se muestra mientras el jugador está en disputa: dos barras que crecen desde el centro de la pantalla, verde hacia la derecha (tú) y roja hacia la izquierda (el rival), más un Label de estado ("VAS GANANDO" / "TE ARRASTRAN, TIRA HACIA ATRÁS" / "EMPATE, TIRA HACIA ATRÁS"). El reparto sale de _tug_pull_1 / _tug_pull_2 visto desde el jugador local: empatados = ambas mitades llenas; si tiras más, la verde avanza.

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