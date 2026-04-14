## Jugador — Player controller.
##
## Authority model:
##   • Each Jugador node has multiplayer authority set to its peer id.
##   • Input, camera and visual-layer setup only run on the authority peer.
##   • Physics integration only runs on the authority peer.
##   • Steal resolution is server-authoritative via RPC.
extends RigidBody3D
class_name Jugador

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export_group("Movement")
@export var velocidad_maxima:    float = 6.0
@export var aceleracion_tierra:  float = 20.0

@export_group("Camera")
@export var sensibilidad_raton:  float = 0.003
@export var angulo_mirar_abajo:  float = -60.0   # GDD spec: pitch < -60º activates pocket

@export_group("Gameplay")
@export var tiempo_para_cambiazo: float = 1.5   # GDD spec: 1.5 s hold to steal

# ---------------------------------------------------------------------------
# Node references — resolved in _ready
# ---------------------------------------------------------------------------
@onready var _cabeza:         Node3D         = $Cabeza
@onready var _camara:         Camera3D       = $Cabeza/Camera3D
@onready var _raycast:        RayCast3D      = $Cabeza/RayCast3D
@onready var _mano_der:       Mano           = $Cabeza/ManoDerecha
@onready var _mano_izq:       Mano           = $Cabeza/ManoIzquierda
@onready var _cruceta:        ColorRect      = $Interfaz/Centro/Cruceta
@onready var _visuales:       Node3D         = $ModeloCocodrilo
@onready var _bolsillo_attach: BoneAttachment3D = $ModeloCocodrilo/Armature/Skeleton3D/BolsilloAttachment
@onready var _bulto_visual:   MeshInstance3D = $ModeloCocodrilo/Armature/Skeleton3D/BolsilloAttachment/BultoVisual
@onready var _barra_der:      ProgressBar    = $Interfaz/Centro/BarraCargaDer
@onready var _barra_izq:      ProgressBar    = $Interfaz/Centro/BarraCargaIzq

# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------
var _rot_objetivo_y:    float   = 0.0
var _dir_input:         Vector3 = Vector3.ZERO
var _altura_base_viz:   float   = 0.0
var _objeto_en_bolsillo: ObjetoAgarrable = null

# Steal progress
var _timer_cambiazo:   float        = 0.0
var _victima_cambiazo: Jugador      = null
var _mano_cambiazo:    Mano         = null
var _barra_cambiazo:   ProgressBar  = null

# ---------------------------------------------------------------------------
# Multiplayer authority setup
# ---------------------------------------------------------------------------

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	add_to_group("jugadores")

	if _visuales:
		_altura_base_viz = _visuales.position.y
	if _bulto_visual:
		_bulto_visual.visible = false

	if is_multiplayer_authority():
		_setup_local_player()
	else:
		_setup_remote_player()

func _setup_local_player() -> void:
	_camara.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_mano_der.barra_carga_ui  = _barra_der
	_mano_izq.barra_carga_ui  = _barra_izq
	_mano_izq.es_mano_izquierda = true

	_set_visual_layer(2)   # Local player renders to layer 2 (excluded from own camera)
	_crear_barra_cambiazo()

func _setup_remote_player() -> void:
	_camara.current = false
	set_process_input(false)
	set_physics_process(false)
	set_process(false)
	_set_visual_layer(1)   # Remote players render to layer 1

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		_process_look(event as InputEventMouseMotion)

	var looking_down := rad_to_deg(_cabeza.rotation.x) < angulo_mirar_abajo
	var ray_info     := _get_raycast_info()

	_handle_hand_input(event, "mano_derecha_accion", _mano_der,  looking_down, ray_info)
	_handle_hand_input(event, "mano_izquierda_accion", _mano_izq, looking_down, ray_info)

func _process_look(event: InputEventMouseMotion) -> void:
	_cabeza.rotate_x(-event.relative.y * sensibilidad_raton)
	_cabeza.rotation.x = clamp(_cabeza.rotation.x, deg_to_rad(-90.0), deg_to_rad(80.0))
	_rot_objetivo_y -= event.relative.x * sensibilidad_raton

func _handle_hand_input(
		event:        InputEvent,
		action:       String,
		mano:         Mano,
		looking_down: bool,
		ray_info:     Dictionary) -> void:

	var placing_held  := Input.is_action_pressed("colocar")
	var action_held   := Input.is_action_pressed(action)
	var just_pressed  := event.is_action_pressed(action)
	var placing_event := event.is_action("colocar")
	var mouse_while_placing := placing_held and event is InputEventMouseMotion

	# Only process this hand if something relevant happened.
	if not (event.is_action(action) or placing_event or mouse_while_placing or action_held):
		return

	# ---- Steal logic ----
	if action_held and mano.objeto_agarrado != null:
		if ray_info["cuerpo"] != null and ray_info["cuerpo"].is_in_group("jugadores"):
			var victima := ray_info["cuerpo"] as Jugador
			if victima != null and victima != self and _is_valid_steal_target(victima):
				_update_steal_state(mano, victima, true)
				return

	if not action_held or ray_info["cuerpo"] == null or not ray_info["cuerpo"].is_in_group("jugadores"):
		_update_steal_state(null, null, false)

	if _victima_cambiazo != null:
		return  # Steal in progress — block normal hand logic

	# ---- Pocket logic ----
	if just_pressed and looking_down:
		_handle_pocket_action(mano)
		return

	# ---- Normal hand ----
	mano.gestionar_input(just_pressed, action_held, placing_held, ray_info)

# ---------------------------------------------------------------------------
# Process / Physics
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var input_vec := Input.get_vector("izquierda", "derecha", "adelante", "atras")
	_dir_input     = Vector3(input_vec.x, 0.0, input_vec.y).normalized()
	_process_steal_progress(delta)
	_update_crosshair()
	_animate_visuals(delta)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var new_basis  := Basis(Vector3.UP, _rot_objetivo_y)
	state.transform.basis = new_basis
	var dir_world  := new_basis * _dir_input
	var vel_h      := Vector2(state.linear_velocity.x, state.linear_velocity.z)
	var target_h   := Vector2(dir_world.x, dir_world.z) * velocidad_maxima
	vel_h           = vel_h.move_toward(target_h, aceleracion_tierra * state.step)
	state.linear_velocity = Vector3(vel_h.x, state.linear_velocity.y, vel_h.y)

# ---------------------------------------------------------------------------
# Pocket system
# ---------------------------------------------------------------------------

func _handle_pocket_action(mano: Mano) -> void:
	if mano.objeto_agarrado != null:
		# Put held object into pocket
		var obj := mano.objeto_agarrado
		mano.soltar(false)
		if _objeto_en_bolsillo != null:
			_sacar_de_bolsillo(true, mano)
		_meter_en_bolsillo(obj)
	elif _objeto_en_bolsillo != null:
		_sacar_de_bolsillo(true, mano)

func _meter_en_bolsillo(objeto: ObjetoAgarrable) -> void:
	_objeto_en_bolsillo = objeto
	add_collision_exception_with(objeto)
	objeto.rpc("entrar_en_bolsillo", name.to_int())
	_sync_bulto.rpc(true)

func _sacar_de_bolsillo(equipar: bool, mano_destino: Mano) -> void:
	if _objeto_en_bolsillo == null:
		return
	var objeto := _objeto_en_bolsillo
	_objeto_en_bolsillo = null
	remove_collision_exception_with(objeto)

	var pos_salida := (
		mano_destino.pos_accion.global_position
		if equipar
		else _bolsillo_attach.global_position
	)
	if equipar:
		objeto.global_position = pos_salida
		if objeto.has_method("reset_physics_interpolation"):
			objeto.reset_physics_interpolation()
		objeto.visible = true
		mano_destino.forzar_agarre_inmediato(objeto, pos_salida)
		objeto.rpc("intentar_coger", multiplayer.get_unique_id())
	else:
		objeto.rpc("salir_de_bolsillo", pos_salida)
	_sync_bulto.rpc(false)

# ---------------------------------------------------------------------------
# Steal system
# ---------------------------------------------------------------------------

func _update_steal_state(mano: Mano, victima: Jugador, activo: bool) -> void:
	if not activo:
		_victima_cambiazo  = null
		_mano_cambiazo     = null
		_timer_cambiazo    = 0.0
		if _barra_cambiazo:
			_barra_cambiazo.visible = false
		return

	if _victima_cambiazo != victima:
		_victima_cambiazo = victima
		_mano_cambiazo    = mano
		_timer_cambiazo   = 0.0
		if _barra_cambiazo:
			_barra_cambiazo.visible = true

func _process_steal_progress(delta: float) -> void:
	if _victima_cambiazo == null or _mano_cambiazo == null:
		return
	_timer_cambiazo += delta
	if _barra_cambiazo:
		_barra_cambiazo.value = (_timer_cambiazo / tiempo_para_cambiazo) * 100.0
	if _timer_cambiazo >= tiempo_para_cambiazo:
		_execute_steal()

func _execute_steal() -> void:
	var mi_objeto := _mano_cambiazo.objeto_agarrado
	if mi_objeto == null:
		_update_steal_state(null, null, false)
		return
	var ruta_objeto := mi_objeto.get_path()
	_mano_cambiazo.limpiar_estado_local()
	var id_victima  := _victima_cambiazo.name.to_int()
	var pos_robo    := _mano_cambiazo.pos_accion.global_position
	rpc_id(1, "_server_process_steal", ruta_objeto, id_victima, _mano_cambiazo.name, pos_robo)
	_update_steal_state(null, null, false)

@rpc("any_peer", "call_local", "reliable")
func _server_process_steal(
		ruta_obj: NodePath,
		id_victima: int,
		nombre_mano: String,
		pos_robo: Vector3) -> void:
	if not multiplayer.is_server():
		return

	var obj_entrante := get_node_or_null(ruta_obj) as ObjetoAgarrable
	var victima      := _find_player_by_id(id_victima)
	if victima == null:
		return

	var id_ladron := multiplayer.get_remote_sender_id()
	var ladron    := _find_player_by_id(id_ladron)

	# --- Step 1: Take what the victim has in their pocket (if anything) ---
	var obj_saliente := victima._objeto_en_bolsillo
	if obj_saliente != null:
		# Remove from victim pocket
		victima.rpc("_rpc_clear_pocket")
		# Give it to the thief's hand
		obj_saliente.ejecutar_robo_desde_servidor(id_ladron, pos_robo)
		if ladron != null:
			ladron.rpc("_rpc_receive_object_in_hand", obj_saliente.get_path(), nombre_mano)

	# --- Step 2: Place the thief's held object into the victim's pocket ---
	if obj_entrante != null:
		obj_entrante.rpc("entrar_en_bolsillo", id_victima)
		victima.rpc("_rpc_assign_pocket_object", obj_entrante.get_path())

	# --- Step 3: If victim had nothing in pocket, eject thief's object physically ---
	# GDD: "El objeto expulsado cae al suelo con un leve impulso y sonido físico."
	# This happens when victim pocket was empty but thief had an object — the object
	# goes into the victim's pocket (handled above). Nothing extra to eject in that case.
	#
	# However if the victim had a held object (not in pocket) we do NOT grab it —
	# the swap is pocket-to-pocket only. The victim's held object stays in their hand.

@rpc("any_peer", "call_local", "reliable")
func _rpc_receive_object_in_hand(ruta: NodePath, nombre_mano: String) -> void:
	var objeto := get_node_or_null(ruta) as ObjetoAgarrable
	var mano   := _cabeza.get_node_or_null(nombre_mano) as Mano
	if objeto and mano:
		mano.forzar_agarre_inmediato(objeto, mano.pos_accion.global_position)

@rpc("any_peer", "call_local", "reliable")
func _rpc_assign_pocket_object(ruta: NodePath) -> void:
	if ruta.is_empty():
		_objeto_en_bolsillo = null
		_sync_bulto.rpc(false)
	else:
		_objeto_en_bolsillo = get_node(ruta) as ObjetoAgarrable
		_sync_bulto.rpc(true)

@rpc("any_peer", "call_local", "reliable")
func _rpc_clear_pocket() -> void:
	_objeto_en_bolsillo = null
	_sync_bulto.rpc(false)

# ---------------------------------------------------------------------------
# Gameplay queries
# ---------------------------------------------------------------------------

func tiene_objeto_ilegal() -> bool:
	var der := _mano_der.objeto_agarrado != null and _mano_der.objeto_agarrado.es_ilegal
	var izq := _mano_izq.objeto_agarrado != null and _mano_izq.objeto_agarrado.es_ilegal
	var bol := _objeto_en_bolsillo != null and _objeto_en_bolsillo.es_ilegal
	return der or izq or bol

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_raycast_info() -> Dictionary:
	if _raycast.is_colliding():
		return {
			"cuerpo": _raycast.get_collider(),
			"punto":  _raycast.get_collision_point(),
			"normal": _raycast.get_collision_normal(),
		}
	return { "cuerpo": null, "punto": Vector3.ZERO, "normal": Vector3.UP }

func _is_valid_steal_target(victima: Jugador) -> bool:
	# Must be approaching from behind
	var mi_frente  := -global_transform.basis.z
	var su_frente  := -victima.global_transform.basis.z
	return mi_frente.dot(su_frente) > 0.0

func _find_player_by_id(id: int) -> Jugador:
	for p in get_tree().get_nodes_in_group("jugadores"):
		if p.name.to_int() == id:
			return p as Jugador
	return null

func _set_visual_layer(layer: int) -> void:
	if not _visuales:
		return
	var parts := _visuales.find_child("PartesOcultables", true, false)
	if parts:
		parts.layers = 1 << (layer - 1)

func _crear_barra_cambiazo() -> void:
	_barra_cambiazo = ProgressBar.new()
	if has_node("Interfaz/Centro"):
		$Interfaz/Centro.add_child(_barra_cambiazo)
		_barra_cambiazo.custom_minimum_size = Vector2(200.0, 20.0)
		_barra_cambiazo.show_percentage     = false
		_barra_cambiazo.visible             = false
		_barra_cambiazo.modulate            = Color(1.0, 0.5, 0.0)

# ---------------------------------------------------------------------------
# Visual feedback
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_local")
func _sync_bulto(visible_bulto: bool) -> void:
	if _bulto_visual:
		_bulto_visual.visible = visible_bulto

func _update_crosshair() -> void:
	var looking_down := rad_to_deg(_cabeza.rotation.x) < angulo_mirar_abajo
	var info         := _get_raycast_info()
	var cuerpo       : Node = info["cuerpo"]
	var color        := Color(1, 1, 1, 0.2)

	if cuerpo != null:
		if cuerpo.is_in_group("jugadores"):
			var tiene_obj := _mano_der.objeto_agarrado != null or _mano_izq.objeto_agarrado != null
			color = Color(1.0, 0.5, 0.0, 1.0) if (tiene_obj and _is_valid_steal_target(cuerpo)) else Color(1, 1, 1, 0.5)
		elif cuerpo is RigidBody3D:
			color = Color(1, 0, 0, 1)
		elif cuerpo.has_method("interactuar"):
			color = Color(0, 1, 0, 1)
		elif looking_down and (_mano_der.objeto_agarrado != null or _mano_izq.objeto_agarrado != null or _objeto_en_bolsillo != null):
			color = Color(0.6, 0.0, 0.8, 1.0)
		else:
			color = Color(1, 1, 1, 0.5)
	elif looking_down and (_mano_der.objeto_agarrado != null or _mano_izq.objeto_agarrado != null or _objeto_en_bolsillo != null):
		color = Color(0.6, 0.0, 0.8, 1.0)

	_cruceta.color = color

func _animate_visuals(delta: float) -> void:
	if not _visuales:
		return
	var vel_local          := global_transform.basis.inverse() * linear_velocity
	var speed_h            := Vector2(vel_local.x, vel_local.z).length()
	var target_z: float    = clamp(vel_local.x * 0.15, -0.4, 0.4)
	var target_x: float    = clamp(-vel_local.z * 0.15, -0.4, 0.4)
	_visuales.rotation.z    = lerp_angle(_visuales.rotation.z, -target_z, delta * 5.0)
	_visuales.rotation.x    = lerp_angle(_visuales.rotation.x,  target_x, delta * 5.0)

	if speed_h > 1.0:
		var bounce := absf(sin(Time.get_ticks_msec() * 0.001 * 15.0)) * 0.15
		_visuales.position.y = lerp(_visuales.position.y, _altura_base_viz + bounce, delta * 15.0)
	else:
		_visuales.position.y = lerp(_visuales.position.y, _altura_base_viz, delta * 5.0)
