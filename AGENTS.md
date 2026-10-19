# AGENTS.md — Sistema Autónomo y Especificación Técnica de NOT MY FAULT!

## 0. PROTOCOLO DE TRABAJO AUTÓNOMO (OBLIGATORIO EN CADA TURNO)
Eres el Ingeniero Principal de este proyecto en Godot 4.7.2 (`Jolt Physics`)[cite: 13]. Tienes acceso completo de lectura y escritura al repositorio. **NUNCA pidas al usuario que copie o pegue código ni que te adjunte archivos.** Edita los archivos directamente con tus herramientas y sigue este bucle automático en CADA petición:

1. **Fase 1 - Lectura Automática de Estado:**
   - Antes de escribir código, lee `STATUS.md` para saber qué está hecho (`[x]`) y cuál es la tarea pendiente (`[ ]`).
2. **Fase 2 - Subagentes y Contexto Modular (`docs/`):**
   - Según el área que vayas a tocar, lee por tu cuenta el documento técnico correspondiente sin que el usuario te lo pida:
     - Red, RPCs y autoridad -> Lee `docs/01_architecture_and_netcode.md`[cite: 18]
     - Jugador, manos, bolsillo ciego, cambiazo e inspección -> Lee `docs/02_player_and_inventory.md`[cite: 17]
     - Reloj, Jefe (Ira), votaciones y matriz de victoria -> Lee `docs/03_boss_and_gameloop.md`
   - Si necesitas inspeccionar varios scripts del proyecto para no romper referencias, usa tu herramienta de subagente/exploración para verificar las firmas de las funciones antes de editarlas.
3. **Fase 3 - Ejecución Directa en Código:**
   - Modifica directamente los scripts `.gd` afectados usando tus herramientas de edición de archivos.
   - Aplica **tipado estricto obligatorio** en GDScript 2.0 (`:=`, tipos en parámetros y retornos) y sintaxis exclusiva de Godot 4.
4. **Fase 4 - Auto-Actualización de Documentación (Cierre Automático):**
   - **SIEMPRE**, antes de dar por terminada tu respuesta al usuario, edita tú mismo `STATUS.md` cambiando `[ ]` por `[x]` en la tarea completada.
   - Si durante la programación has añadido una nueva variable exportada importante, señal o cambio arquitectónico, actualiza también el archivo correspondiente dentro de `docs/` para que la documentación nunca quede desfasada.

---

## 1. Mapa de Arquitectura y Clases Reales del Proyecto

### Autoloads y Managers
- `GameManager` (`res://autoload/game_manager.gd`)[cite: 4, 13]:
  - Enums: `Phase { LOBBY, WORKING, BOSS_INSPECTION, BOARDROOM_VOTING, ENDED }`, `Role { UNASSIGNED, INNOCENT, LIABILITY }`[cite: 4, 16].
  - Estado sincronizado (Server-only mutation): `current_phase`, `roles: Dictionary`, `broken_object_repaired: bool`[cite: 4].
- `ControladorTiempo` (`res://levels/TimeManager.gd`, grupo `"proveedor_tiempo"`)[cite: 3, 7]:
  - Controla `duracion_jornada` (480.0s = 8 min) y `tiempo_restante`[cite: 7, 16, 19]. Al llegar a 0 llama a `GameManager.trigger_end_of_day()`[cite: 7, 19].
- `BossManager` (`res://levels/bossmanager.gd`, grupo `"boss_manager"`)[cite: 3, 8]:
  - Controla `ira_actual` [0.0 .. 100.0] y `estado_actual` (`BossState { WORKING, SUSPICIOUS, INSPECTING }`)[cite: 8].
  - Método público RPC: `agregar_caos(cantidad: float)` (positivo sube ira, negativo la reduce)[cite: 8]. Al llegar a `ira_maxima` dispara `GameManager.trigger_boss_inspection()`[cite: 8, 19].

### Jugador y Manos (`RigidBody3D` + Spring Physics)
- `Jugador` (`res://entities/player/jugador.gd`, grupo `"jugadores"`)[cite: 3, 5]:
  - `extends RigidBody3D`. Autoridad asignada a `name.to_int()`[cite: 5, 18].
  - Nodos clave: `$Cabeza/Camera3D`, `$Cabeza/RayCast3D`, `$Cabeza/ManoDerecha`, `$Cabeza/ManoIzquierda`, `$ModeloCocodrilo/Armature/Skeleton3D/BolsilloAttachment/BultoVisual`[cite: 5].
  - **Bolsillo Ciego:** Variable `_objeto_en_bolsillo: ObjetoAgarrable`[cite: 5, 17]. Se activa mirando abajo (`rad_to_deg(_cabeza.rotation.x) < angulo_mirar_abajo` [-60º]) + acción de mano[cite: 5, 17]. Cero UI de inventario[cite: 15, 16, 17].
  - **Espalda (Cambiazo / Inspección):** 1.5s manteniendo acción apuntando a la espalda de otro `Jugador` (`_is_valid_steal_target` comprueba `dot > 0.0`)[cite: 5, 17]. Resuelto en el servidor[cite: 5, 17].
- `Mano` (`res://entities/hand/mano.gd`)[cite: 3, 6]:
  - `extends Node3D`. Gestiona `objeto_agarrado: ObjetoAgarrable`, lanzamiento con barra de carga (`barra_carga_ui`), golpe/uso corto (`usar_objeto`) y modo colocación con fantasma (`colocar` = tecla E)[cite: 6, 16].
  - Envía la posición objetivo al servidor vía `objeto_agarrado.rpc("actualizar_objetivo_agarre", pos_destino, rot_destino, id)`[cite: 6, 18].

### Objetos e Interactuables
- `ObjetoAgarrable` (`res://objects/grabables/objeto_agarrable.gd`, grupos `"agarrables"` e `"ilegal"`)[cite: 3, 9]:
  - `extends RigidBody3D`. Físicas autoritativas en el servidor mediante fuerzas de muelle (`_apply_spring_forces`) en `_integrate_forces`[cite: 9, 18].
  - Cuando entra en bolsillo (`entrar_en_bolsillo`), se congela (`freeze = true`), apaga colisiones y se envía a `LIMBO_POSITION = Vector3(0, -200, 0)`[cite: 9, 17, 18].
- `Documento` (`res://objects/grabables/documento.gd`) y `Sello` (`res://objects/grabables/sello.gd`): Hijos de `ObjetoAgarrable` para la tarea de sellado[cite: 3, 10, 11].
- `Interactuable` (`res://objects/interactables/interactuable.gd`): `extends StaticBody3D`. Clase base para estaciones fijas (`bandeja_entrada.gd`, `bandeja_salida.gd`, `telefono_rojo.gd`, `maquina_fichar.gd`)[cite: 3, 12].

---

## 2. Reglas Inquebrantables de Red y Físicas
1. **Autoridad de Objetos (`ObjetoAgarrable`):** Permanece SIEMPRE en el Servidor (peer 1)[cite: 18]. Los clientes piden acciones por `@rpc("any_peer", "call_local")`[cite: 9, 18].
2. **Validación en Servidor:** Toda acción de estado, robo, inspección o voto DEBE empezar con `if not multiplayer.is_server(): return`[cite: 4, 5, 18].
3. **Prohibido romper escenas (`.tscn`):** No renombres nodos referenciados con `@onready` ni cambies rutas sin actualizar su escena.