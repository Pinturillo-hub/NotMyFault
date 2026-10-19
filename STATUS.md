STATUS.md - Progreso Técnico de NOT MY FAULT!

Fase 1: Prototipo Core / Sandbox Local

1. Sistema de Físicas y Agarre
[x] Control 1ª persona básico con inercia (jugador.gd).
[x] Copias remotas de Jugador congeladas (FREEZE_MODE_KINEMATIC) y animadas desde el delta de posición sincronizada (sin simular gravedad local en Jolt).
[x] Manos físicas con Spring Joint (fuerza de muelle) desde el servidor (mano.gd, objeto_agarrable.gd).
[x] Sistema de lanzamiento de objetos (barra de carga visual).
[x] Modo fantasma para colocación precisa (Tecla E).
[x] Lógica de forcejeo (Tug-of-War) entre dos jugadores.

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
[ ] Exigir activación simultánea por 2 jugadores distintos.
[ ] Implementar fase de Votación (Phase.BOARDROOM_VOTING) de 45 segundos con teletransporte de jugadores. (45 s y votación ya implementados; falta el teletransporte a la Sala de Juntas).
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

Fase 2: Multijugador y Sistema de Roles (Próximamente)
[ ] Implementar NetworkManager Autoload (GodotSteam, P2P Relay).
[x] Configurar MultiplayerSpawner para spawnear Jugador.tscn (configurado en levels/sandbox.tscn sobre el nodo "Jugadores").
[ ] Programar lógica pasiva/activa de los 8 Sub-Roles (Cafeinómano, Escaqueado, etc.).
[ ] Implementar Voice Chat posicional mediante API de Steam.
