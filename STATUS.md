STATUS.md - Progreso Técnico de NOT MY FAULT!

Fase 1: Prototipo Core / Sandbox Local

1. Sistema de Físicas y Agarre
[x] Control 1ª persona básico con inercia (jugador.gd).
[x] Copias remotas de Jugador congeladas (FREEZE_MODE_KINEMATIC) y animadas desde el delta de posición sincronizada (sin simular gravedad local en Jolt).
[x] Manos físicas con Spring Joint (fuerza de muelle) desde el servidor (mano.gd, objeto_agarrable.gd).
[x] Clases de peso (ObjetoAgarrable.Peso: LIGERO, MEDIO, PESADO) como única fuente de verdad. CONFIG_PESO define masa física, respuesta del muelle, gravedad al sostener, ralentización, multiplicador de lanzamiento, tirón máximo y tropiezo. No se usan kg por escena: la masa se deriva de la clase en _ready.
[x] LIGERO (Documento, Sello, CajaRota): masa 0.8, sin ralentización, muelle normal, lanzamiento x1.3, nunca se rompe el agarre.
[x] MEDIO (CajaPrueba): masa 5, ralentización 0.85, muelle 0.6, lanzamiento x0.6, nunca se rompe el agarre.
[x] PESADO (Mesa2): masa 25, ralentización 0.5, gravedad activa mientras se sostiene y servo de arrastre (velocidad máx. 3.4 m/s) en _apply_drag(): se arrastra pero no se puede levantar. Lanzamiento x0.3.
[x] Golpes por peso: se eliminaron las excepciones de colisión con todos los jugadores (solo queda la del portador). El impulso real depende de la masa de la clase y de la masa del jugador (70 kg), así un ligero apenas empuja, uno medio da un golpe moderado y uno pesado empuja fuerte.
[x] Tirón roto (solo PESADO): Mano._comprobar_tiron() mide la distancia mano-punto de agarre; si supera tiron_max (1.2 m) tras 0.8 s de gracia, el objeto se suelta, la mano vuelve a reposo y Jugador.tropezar() aplica 3.5 m/s de lurch y 0.9 s sin control con frenado reducido.
[x] Tropiezo con vuelco: Jugador.tropezar() ahora lanza un Tween que vuelca el modelo (~80º) y acompaña la cámara, con una fracción de caída y el resto para levantarse rápido (angulo_volcado, angulo_volcado_camara, roll_volcado, fraccion_caida exportados). Se deduplica si ambas manos detectan el tirón a la vez.
[x] Tumbarse por impacto: ObjetoAgarrable activa contact_monitor y, si un objeto lanzado golpea a un jugador, el servidor compara la carga del lanzamiento con fuerza_tropiezo de la clase (ligero 90%, medio 50%, pesado 70%) y envía _rpc_tropiezo al cliente de la víctima. Cooldown 600 ms; el lanzador no se tumba a sí mismo.
[x] Indicador de agarre: barra inferior central que se llena y pasa de verde a rojo según la tensión del agarre (distancia/tiron_max) de los objetos que pueden romperse (pesados), para avisar de lo cerca que se está de tropezar.
[x] Al caer se sueltan las manos: Jugador._soltar_manos() hace soltar a cualquiera de las dos manos lo que sujeten cuando tropezar() se dispara (tirón roto o impacto).
[x] Agarre a dos manos sobre el mismo objeto: el segundo intentar_coger() del mismo jugador activa agarre_doble (sin forcejeo) y multiplica el muelle/arrastre por FUERZA_DOS_MANOS (1.8) y la ralentización por BONUS_DOS_MANOS (1.4, tope 1.0). Solo la mano derecha envía objetivos físicos cuando ambas sujetan lo mismo.
[x] Lanzamiento por peso: Mano.soltar() trata velocidad_lanzamiento (4..12 m/s) como velocidad objetivo y la convierte en impulso (velocidad * masa * factor de clase), de modo que los ligeros vuelan rápido y los pesados apenas salen.
[x] Bolsillo y Cambiazo: los objetos PESADOS no se pueden guardar en el bolsillo ("Demasiado pesado...") ni usar para un Cambiazo (se valida en servidor).
[x] Botón de mano: click corto (< tiempo_para_lanzar) deja el objeto pegado (agarre débil); mantener el click es el "agarre fuerte" (solo se lleva mientras se mantiene; al soltar el objeto cae). Ya no se muestra la barra de carga mientras se mantiene.
[x] Modo fantasma para colocación precisa (Tecla E).
[x] Lanzamiento por giro de cámara: mantener el click y mover/girar la cámara por encima de giro_minimo (1 rad/s) lanza el objeto en la dirección del giro con velocidad objetivo 2..5 m/s x factor de peso (poca intensidad); por debajo, soltar solo suelta. La velocidad se IMPONE (linear_velocity = velocidad_final) para que la inercia de la mano no se sume.
[x] Robo desde la mano: apuntando al objeto que otro sostiene, un click lo arrebata si la víctima lo lleva con agarre débil (click simple); si la víctima mantiene el click (agarre fuerte) el ladrón debe mantener también el click e iniciar un forcejeo.
[x] Forcejeo (tug-of-war) real entre dos jugadores: el objeto queda colgado entre ambos y no persigue a ninguna mano; cada uno tira alejando la mano (arrastrando el ratón o caminando hacia atrás) y el servidor acumula el tirón de cada uno. Al alcanzar TUG_UMBRAL (4 m de tirón total) o agotar TUG_DURACION_MAX (6 s), quien tiró más se queda el objeto y el otro tropieza. Si uno suelta el click durante la disputa, ambos tropiezan y el objeto sale disparado (TUG_ESCAPE_SPEED = 7 m/s).
[x] UI de potencia de agarre: dos barras que crecen desde el centro (verde tú a la derecha, roja el rival a la izquierda) más un Label de estado ("VAS GANANDO" / "TE ARRASTRAN, TIRA HACIA ATRÁS" / "EMPATE...").

2. Gestión de Inventario y Bolsillo Ciego
[x] Input para guardar (Pitch < -60º).
[x] Desactivación de colisiones al entrar al bolsillo (modo Limbo).
[x] Aparición de "Bulto Genérico" en la malla trasera del personaje al guardar algo.
[x] Forzar "sacar a la mano" para comprobar inventario (Sin UI).

3. Tareas (Vertical Slice)
[x] Tarea 1 (Sellado): Bandeja de entrada + Sello físico con temporizador + Bandeja de salida que elimina el documento.
[x] Conectar Bandeja de salida con BossManager para reducir Ira al sellar bien.
[ ] Implementar Tarea 2: Cafetera Explosiva (físicas inestables).
[ ] Implementar Tarea 3: Fotocopiadora Rebelde (botones interactuables).
[ ] Implementar Tarea 4: Destructora de Papel.
[ ] Implementar Tarea 5: Servidor Recalentado.

4. El Jefe y el Reloj
[x] TimeManager.gd creado (bucle de cuenta atrás).
[x] Ajustar reloj a 8 minutos reales (480.0 segundos).
[x] BossManager.gd creado con acumulación pasiva y activa de Ira.
[x] Ajustar multiplicador pasivo de Ira para partidas de 8 mins (~0.3 / s).
[x] Completar evaluación de la Matriz Lógica en _run_inspection_logic() distinguiendo Objeto Roto vs Reparado en su pedestal.

5. Mecánicas de Espalda (Social Deduction)
[x] "El Cambiazo" (Robar/Introducir en el bolsillo trasero) con barra circular (1.5s).
[x] Restringir "El Cambiazo" exclusivamente al rol de Culpable (validado en cliente y servidor).
[x] Implementar "La Inspección Arriesgada" (Leer pista_inspeccion sin robar, mano vacía, 1.5s, solo el inspector recibe la pista).
[x] Corregir la detección de espalda cliente→host: ShapeCast3D horizontal a la altura del pecho como respaldo del RayCast3D, porque la cámara (~1.09 m) queda por encima de la cápsula del jugador (~1.02 m) y el rayo pasaba sobre la cabeza del host.
[x] Imprimir el rol local en consola con "[ROL] peer <id> = TORPE/INOCENTE" y mostrar un Label local de rol en builds de depuración, para diagnosticar por qué un cliente no puede iniciar el Cambiazo (rol INOCENTE).

6. Sistema de Sala de Juntas (Teléfono Rojo)
[x] Teléfono Rojo funcional: escena objects/interactables/telefono_rojo.tscn (StaticBody3D + MeshInstance3D + CollisionShape3D, script Interactuable) instanciada en sandbox.tscn. Al interactuar en Phase.WORKING inicia GameManager.start_voting() y abre el VotingUI.
[x] Exigir activación simultánea por 2 jugadores distintos: TelefonoRojo acumula _activaciones (peer_id → ticks) y solo llama a start_voting() cuando 2 ids distintos pulsan dentro de VENTANA_ACTIVACION = 3 s. Label3D "1/2" sincronizado con _rpc_set_estado y Timer de ventana que reinicia el contador.
[x] Implementar fase de Votación (Phase.BOARDROOM_VOTING) de 45 segundos con teletransporte de jugadores: al arrancar la reunión GameManager guarda las posiciones previas y reparte a los jugadores en un círculo de 2.2 m alrededor del nodo SalaJuntas (grupo "sala_juntas" + PuntoCentro, con mesa y cartel en sandbox.tscn). Si la reunión es inconcluyente los devuelve a su sitio. Reabrir la papeleta con la tecla V durante la reunión.
[x] Bloquear el movimiento WASD durante toda la reunión (Jugador._process pone _dir_input a ZERO en Phase.BOARDROOM_VOTING) y mostrar un contador de 45 s arriba en el centro que crece y se tiñe de rojo al acercarse a 0 (Label "Contador" en VotingUI, alimentado por GameManager.voting_time_left, que ahora decrementa en todos los peers; solo el servidor resuelve).
[x] Auto-voto al agotarse el tiempo: _resolve_vote() rellena con el propio id el voto de quien no votó ("el voto va contra ti mismo") antes de contar.
[x] Feedback provisional al resolver la votación: _broadcast_end/_broadcast_resultado muestran un cartel grande con el veredicto (VOTE_CORRECT/VOTE_WRONG y también el resto de finales) en placeholders; la reunión inconcluyente muestra "REUNIÓN INCONCLUYENTE" durante 2.5 s antes de devolver a la oficina.
[x] Implementar lógica de Mayoría Cualificada ($\ge 50\%$), empates/dispersión -> "Reunión Inconcluyente" (+25% Ira, teléfono roto).

7. Correcciones de Red para Partidas con Varios Clientes
[x] Spawn de jugadores solo en el servidor, con guarda anti-duplicados por nombre y eliminación del jugador al desconectarse (ui/menu_principal.gd).
[x] Eliminar el spam de "on_spawn_receive: parent->has_node(name)": la Bandeja de Entrada ya no arranca su Timer en clientes antes de unirse; solo genera documentos en el servidor y durante Phase.WORKING (objects/interactables/bandeja_entrada.gd).
[x] Sincronizar Phase.WORKING en los clientes al recibir el diccionario de roles (_sync_roles).
[x] Corregir el RPC de la Inspección Arriesgada: el servidor no es la autoridad del nodo Jugador del cliente, así que _rpc_recibir_pista usa "any_peer" y valida que el remitente sea el peer 1.
[x] Añadir GameManager.es_servidor_activo() para no llamar a multiplayer.is_server() con el peer desconectado (elimina el spam de "multiplayer instance isn't currently active").
[x] Reloj y Jefe solo avanzan en un servidor activo (TimeManager / BossManager), no en clientes que cargaron la escena antes de unirse.
[x] Corregir el RPC "_activate_ghost_mode is not allowed" al usar el Sello: el modo fantasma es authority-only y ahora solo lo dispara el servidor (objeto_agarrable.gd).
[x] Corregir la extracción del bolsillo: se emite salir_de_bolsillo antes de intentar_coger para teletransportar el objeto fuera del limbo, evitando que el muelle lo arrastre ~200 m y que la mano desaparezca por el timeout.
[x] Limpiar las excepciones de colisión del portador anterior al entrar en el bolsillo (objeto_agarrable.gd).
[x] Al colocar un objeto en el suelo (modo fantasma), liberar también el agarre en el servidor con intentar_soltar para que no quede marcado como sostenido (mano.gd).
[x] Corregir el crash de la tecla E al colocar un objeto ("Invalid assignment of property 'global_rotation' ... on a base object of type 'Nil'", mano.gd): _broadcast_state() es call_local y, al soltar, emite disputa_finalizada de forma sincrónica en el host, lo que deja objeto_agarrado = null. _execute_placement() ahora guarda una referencia local (var obj) antes de los RPCs.
[x] Corregir el teletransporte a la Sala de Juntas: separar Jugador.teleport_to() (llamada local del host) del RPC _rpc_teleport_to_boardroom (clientes, valida sender == 1), porque al invocar la función @rpc directamente desde el contexto de la RPC de un cliente get_remote_sender_id() devuelve el id de ese cliente y la rechazaba. Además el desplazamiento se aplica en _integrate_forces (no asignando global_position), para que el servidor de físicas no lo sobrescriba.

Fase 2: Multijugador y Sistema de Roles (Próximamente)
[ ] Implementar NetworkManager Autoload (GodotSteam, P2P Relay).
[x] Configurar MultiplayerSpawner para spawnear Jugador.tscn (configurado en levels/sandbox.tscn sobre el nodo "Jugadores").
[ ] Programar lógica pasiva/activa de los 8 Sub-Roles (Cafeinómano, Escaqueado, etc.).
[ ] Implementar Voice Chat posicional mediante API de Steam.
