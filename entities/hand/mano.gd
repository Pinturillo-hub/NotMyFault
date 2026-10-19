## Mano — Hand controller attached to the player's head.
##
## Manages: grab, throw, place-mode ghost, charge bar UI.
## Does NOT own physics authority — that belongs to ObjetoAgarrable.
extends Node3D
class_name Mano

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
@export var es_mano_izquierda: bool = false
@export var fuerza_lanzamiento: float = 6.0
@export var fuerza_lanzamiento_maxima: float = 20.0
@export var offset_reposo_cuerpo: Vector3 = Vector3(0.4, 1.0, -0.6)

@export_group("Timings")
@export var tiempo_para_lanzar:  float = 0.3
@export var tiempo_carga_maxima: float = 2.0
@export var tiempo_limite_caida: float = 3.0

# Set by Jugador after instantiation
var barra_carga_ui: ProgressBar = null

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var _mesh:       MeshInstance3D = $MeshMano
@onready var pos_accion:  Marker3D       = $PosicionAccion
@onready var _jugador:    Node3D         = get_parent().get_parent()

# ---------------------------------------------------------------------------
# Public state (read by Jugador for steal logic)
# ---------------------------------------------------------------------------
var objeto_agarrado: ObjetoAgarrable = null

# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------
var _tiempo_pulsado:        float = 0.0
var _esta_pulsando:         bool  = false
var _ignorar_soltar:        bool  = false
var _modo_manosear:         bool  = false
var _punto_agarre_local:    Vector3 = Vector3.ZERO
var _en_disputa_activa:     bool  = false
var _tiempo_desde_agarre:   float = 0.0
var _z_original_accion:     float = 0.0
var _tween_activo:          Tween = null

# Placement mode
var _modo_colocacion:       bool  = false
var _colocacion_cancelada:  bool  = false
var _colocando_prev:        bool  = false   # edge-detect E key
var _fantasma:              MeshInstance3D = null
var _mat_fantasma:          StandardMaterial3D = null
var _pos_fantasma_final:    Vector3 = Vector3.ZERO
var _rot_fantasma_final:    Vector3 = Vector3.ZERO

const MAX_SLOPE_DEG: float = 45.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_z_original_accion = pos_accion.position.z

	_mat_fantasma = StandardMaterial3D.new()
	_mat_fantasma.albedo_color       = Color(1, 0, 0, 0.6)
	_mat_fantasma.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_fantasma.cull_mode          = BaseMaterial3D.CULL_DISABLED
	_mat_fantasma.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED

	await get_tree().process_frame
	if _jugador:
		_update_visuals(0.0)

func _physics_process(delta: float) -> void:
	_update_hold_timer(delta)
	_update_held_object()
	_update_visuals(delta)

func _update_hold_timer(delta: float) -> void:
	if _esta_pulsando and objeto_agarrado != null and not _ignorar_soltar and not _modo_colocacion:
		_tiempo_pulsado += delta
		if _tiempo_pulsado >= tiempo_limite_caida:
			# Object slipped
			soltar(false)
			_reset_input_state()
		else:
			_set_charge_bar_visible(true, _tiempo_pulsado / tiempo_limite_caida)
	else:
		_set_charge_bar_visible(false)

func _update_held_object() -> void:
	if objeto_agarrado == null:
		return
	_tiempo_desde_agarre += get_physics_process_delta_time()
	# If we lost authority (someone else grabbed it), clean up
	if _tiempo_desde_agarre > 0.5 and not _en_disputa_activa:
		if is_instance_valid(objeto_agarrado) and objeto_agarrado.id_sostenedor_1 != multiplayer.get_unique_id():
			limpiar_estado_local()
			return
	if is_instance_valid(objeto_agarrado):
		_send_physics_data()

# ---------------------------------------------------------------------------
# Main input entry — called by Jugador
# ---------------------------------------------------------------------------

func gestionar_input(
		just_pressed:    bool,
		is_pressed:      bool,
		is_placing_held: bool,
		info:            Dictionary) -> void:

	_esta_pulsando = is_pressed

	var e_just_pressed  := is_placing_held and not _colocando_prev
	var e_just_released := not is_placing_held and _colocando_prev
	_colocando_prev      = is_placing_held

	# ---- Placement mode ----
	if objeto_agarrado != null:
		if e_just_pressed:
			_start_placement_mode()

		if _modo_colocacion:
			if just_pressed:
				_colocacion_cancelada = true
				_clear_ghost()
			if not _colocacion_cancelada:
				_update_ghost(info)

		if e_just_released and _modo_colocacion:
			if not _colocacion_cancelada and _fantasma != null and _fantasma.visible:
				_execute_placement()
			_clear_ghost()
			_modo_colocacion    = false
			_colocacion_cancelada = false

	if _modo_colocacion or _colocacion_cancelada:
		return

	# ---- Interaction while holding object ----
	if objeto_agarrado != null and just_pressed and info["cuerpo"] != null:
		if info["cuerpo"].has_method("interactuar"):
			info["cuerpo"].interactuar()
			return  # Don't proceed with grab/throw logic

	# ---- Normal action ----
	if just_pressed:
		_tiempo_pulsado = 0.0
		if objeto_agarrado == null:
			if info["cuerpo"] != null:
				if info["cuerpo"].has_method("interactuar"):
					info["cuerpo"].interactuar()
					_modo_manosear  = true
					_ignorar_soltar = true
				elif info["cuerpo"] is RigidBody3D:
					_try_grab(info["cuerpo"] as ObjetoAgarrable, info["punto"])
					_ignorar_soltar = true
			else:
				_modo_manosear = true
		else:
			_ignorar_soltar = false

	if is_pressed:
		if objeto_agarrado == null and not _ignorar_soltar:
			_modo_manosear = true
	else:
		_modo_manosear = false
		if not just_pressed:
			if objeto_agarrado != null and not _ignorar_soltar:
				_decide_final_action()
			_ignorar_soltar = false
			_tiempo_pulsado = 0.0

# ---------------------------------------------------------------------------
# Grab
# ---------------------------------------------------------------------------

func _try_grab(cuerpo: ObjetoAgarrable, punto_impacto: Vector3) -> void:
	if cuerpo == null:
		return
	_connect_dispute_signals(cuerpo)
	cuerpo.rpc("intentar_coger", multiplayer.get_unique_id())
	objeto_agarrado      = cuerpo
	_punto_agarre_local  = cuerpo.to_local(punto_impacto)
	_tiempo_desde_agarre = 0.0
	if _jugador:
		_jugador.add_collision_exception_with(cuerpo)

## Called by Jugador's steal system to force an immediate grab without going through RPC flow.
func forzar_agarre_inmediato(cuerpo: ObjetoAgarrable, posicion_mundo: Vector3) -> void:
	limpiar_estado_local()
	objeto_agarrado      = cuerpo
	_punto_agarre_local  = cuerpo.to_local(posicion_mundo)
	_tiempo_desde_agarre = 0.0
	_ignorar_soltar      = true
	if _jugador:
		_jugador.add_collision_exception_with(cuerpo)
	cuerpo.visible          = true
	cuerpo.global_position  = posicion_mundo
	if cuerpo.has_method("reset_physics_interpolation"):
		cuerpo.reset_physics_interpolation()
	_mesh.global_position = posicion_mundo

# ---------------------------------------------------------------------------
# Release / Throw
# ---------------------------------------------------------------------------

func soltar(lanzar: bool, fuerza_custom: float = -1.0) -> void:
	if objeto_agarrado == null:
		return
	var fuerza  := fuerza_custom if fuerza_custom >= 0.0 else fuerza_lanzamiento
	var impulso := -pos_accion.global_transform.basis.z * fuerza if lanzar else Vector3.ZERO
	objeto_agarrado.rpc("intentar_soltar", multiplayer.get_unique_id(), impulso)
	limpiar_estado_local()

func limpiar_estado_local() -> void:
	if objeto_agarrado != null:
		if _jugador:
			_jugador.remove_collision_exception_with(objeto_agarrado)
		_disconnect_dispute_signals(objeto_agarrado)
	objeto_agarrado     = null
	_en_disputa_activa  = false
	_punto_agarre_local = Vector3.ZERO
	_set_charge_bar_visible(false)

func _decide_final_action() -> void:
	if objeto_agarrado == null:
		return
	if _tiempo_pulsado < tiempo_para_lanzar:
		if objeto_agarrado.has_method("usar_objeto"):
			objeto_agarrado.rpc("usar_objeto")
		if objeto_agarrado.usar_animacion_golpe:
			_animate_strike(objeto_agarrado.distancia_golpe)
		else:
			_animate_use_soft()
	else:
		var rango: float  = tiempo_carga_maxima - tiempo_para_lanzar
		var carga: float  = clamp((_tiempo_pulsado - tiempo_para_lanzar) / rango, 0.0, 1.0)
		var fuerza: float = lerp(fuerza_lanzamiento, fuerza_lanzamiento_maxima, carga)
		soltar(true, fuerza)

# ---------------------------------------------------------------------------
# Placement mode
# ---------------------------------------------------------------------------

func _start_placement_mode() -> void:
	_modo_colocacion    = true
	_colocacion_cancelada = false
	_set_charge_bar_visible(false)
	_clear_ghost()

	var mesh_node := _find_mesh_node(objeto_agarrado)
	if mesh_node == null:
		_colocacion_cancelada = true
		return

	_fantasma = MeshInstance3D.new()
	get_tree().root.add_child(_fantasma)
	_fantasma.mesh  = mesh_node.mesh
	_fantasma.scale = objeto_agarrado.scale * mesh_node.scale
	for i in _fantasma.mesh.get_surface_count():
		_fantasma.set_surface_override_material(i, _mat_fantasma)

func _update_ghost(info: Dictionary) -> void:
	if _fantasma == null:
		return
	var punto  : Vector3 = info.get("punto",  Vector3.ZERO)
	var normal : Vector3 = info.get("normal", Vector3.UP)

	if punto == Vector3.ZERO:
		_fantasma.visible = false
		return

	var slope_deg := rad_to_deg(normal.angle_to(Vector3.UP))
	if slope_deg > MAX_SLOPE_DEG:
		_fantasma.visible = false
		return

	_fantasma.visible = true
	_fantasma.global_position = punto
	if normal.is_normalized() and not normal.is_zero_approx():
		_align_y_to_normal(_fantasma, normal)
	_pos_fantasma_final = _fantasma.global_position
	_rot_fantasma_final = _fantasma.global_rotation

func _execute_placement() -> void:
	if objeto_agarrado == null:
		return
	objeto_agarrado.rpc("salir_de_bolsillo", _pos_fantasma_final)
	# Release on the server as well; otherwise the object stays marked as held
	# (stale id_sostenedor_1 / collision exception) after being placed.
	objeto_agarrado.rpc("intentar_soltar", multiplayer.get_unique_id(), Vector3.ZERO)
	objeto_agarrado.global_rotation = _rot_fantasma_final
	objeto_agarrado.linear_velocity  = Vector3.ZERO
	objeto_agarrado.angular_velocity = Vector3.ZERO
	limpiar_estado_local()

func _clear_ghost() -> void:
	if _fantasma != null:
		_fantasma.queue_free()
		_fantasma = null

func _find_mesh_node(root: Node) -> MeshInstance3D:
	if "malla_normal" in root and root.malla_normal is MeshInstance3D:
		return root.malla_normal
	for child in root.get_children():
		if child is MeshInstance3D and child.visible:
			return child
		for grandchild in child.get_children():
			if grandchild is MeshInstance3D and grandchild.visible:
				return grandchild
	return null

func _align_y_to_normal(node: Node3D, new_y: Vector3) -> void:
	var z_orig := node.global_transform.basis.z
	var x_new  := new_y.cross(z_orig).normalized()
	if x_new.is_zero_approx():
		x_new = new_y.cross(Vector3.RIGHT).normalized()
	var z_new := x_new.cross(new_y).normalized()
	node.global_transform.basis = Basis(x_new, new_y, z_new)

# ---------------------------------------------------------------------------
# Physics sync
# ---------------------------------------------------------------------------

func _send_physics_data() -> void:
	var offset_rotado  := objeto_agarrado.global_transform.basis * _punto_agarre_local
	var pos_destino    := pos_accion.global_position - offset_rotado
	var rot_destino    := Quaternion(pos_accion.global_transform.basis.orthonormalized())
	objeto_agarrado.rpc("actualizar_objetivo_agarre", pos_destino, rot_destino, multiplayer.get_unique_id())

# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------

func _update_visuals(delta: float) -> void:
	if objeto_agarrado != null and is_instance_valid(objeto_agarrado):
		var destino := objeto_agarrado.to_global(_punto_agarre_local)
		var dist_sq := _mesh.global_position.distance_squared_to(destino)
		if dist_sq > 2.25 or dist_sq < 0.0001:
			_mesh.global_position = destino
			_mesh.rotation        = objeto_agarrado.global_rotation
		else:
			_mesh.global_position = _mesh.global_position.lerp(destino, delta * 40.0)
			var dir := (destino - _mesh.global_position).normalized()
			if not dir.is_zero_approx() and absf(dir.dot(Vector3.UP)) < 0.99:
				_mesh.look_at(destino, Vector3.UP)
	elif _modo_manosear:
		_interpolate_rest(pos_accion.global_position, pos_accion.global_rotation, delta)
	elif _jugador != null:
		var offset_final := offset_reposo_cuerpo
		offset_final.x = -absf(offset_final.x) if es_mano_izquierda else absf(offset_final.x)
		_interpolate_rest(_jugador.to_global(offset_final), _jugador.global_rotation, delta)
	else:
		_interpolate_rest(global_position, global_rotation, delta)

func _interpolate_rest(dest: Vector3, rot_dest: Vector3, delta: float) -> void:
	_mesh.global_position   = _mesh.global_position.lerp(dest, delta * 20.0)
	_mesh.global_rotation.x = lerp_angle(_mesh.global_rotation.x, rot_dest.x, delta * 15.0)
	_mesh.global_rotation.y = lerp_angle(_mesh.global_rotation.y, rot_dest.y, delta * 15.0)
	_mesh.global_rotation.z = lerp_angle(_mesh.global_rotation.z, rot_dest.z, delta * 15.0)

# ---------------------------------------------------------------------------
# Animations
# ---------------------------------------------------------------------------

func _animate_strike(distancia: float) -> void:
	if _tween_activo and _tween_activo.is_valid():
		_tween_activo.kill()
	if objeto_agarrado != null:
		objeto_agarrado.rpc("modificar_rigidez_temporal", 10.0, 0.3)
	_tween_activo = create_tween()
	_tween_activo.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var objetivo := _z_original_accion - distancia * 1.5
	_tween_activo.tween_property(pos_accion, "position:z", objetivo, 0.1)
	_tween_activo.tween_property(pos_accion, "position:z", _z_original_accion, 0.2)

func _animate_use_soft() -> void:
	if _tween_activo and _tween_activo.is_valid():
		_tween_activo.kill()
	_tween_activo = create_tween()
	_tween_activo.tween_property(_mesh, "position:z", -0.2, 0.05)
	_tween_activo.tween_property(_mesh, "position:z",  0.0, 0.05)

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func _set_charge_bar_visible(visible_flag: bool, ratio: float = 0.0) -> void:
	if barra_carga_ui == null:
		return
	barra_carga_ui.visible = visible_flag
	if visible_flag:
		barra_carga_ui.value = ratio * 100.0
		if _tiempo_pulsado < tiempo_para_lanzar:
			barra_carga_ui.modulate = Color.GREEN
		elif _tiempo_pulsado < tiempo_carga_maxima:
			barra_carga_ui.modulate = Color.YELLOW
		else:
			barra_carga_ui.modulate = Color.RED
	else:
		barra_carga_ui.value = 0.0

# ---------------------------------------------------------------------------
# Dispute signal wiring
# ---------------------------------------------------------------------------

func _reset_input_state() -> void:
	_tiempo_pulsado = 0.0
	_esta_pulsando  = false
	_ignorar_soltar = true
	_modo_manosear  = false
	_set_charge_bar_visible(false)

func _connect_dispute_signals(obj: ObjetoAgarrable) -> void:
	if not obj.disputa_iniciada.is_connected(_on_disputa_iniciada):
		obj.disputa_iniciada.connect(_on_disputa_iniciada.bind(obj))
		obj.disputa_finalizada.connect(_on_disputa_finalizada)

func _disconnect_dispute_signals(obj: ObjetoAgarrable) -> void:
	if not is_instance_valid(obj):
		return
	if obj.disputa_iniciada.is_connected(_on_disputa_iniciada):
		obj.disputa_iniciada.disconnect(_on_disputa_iniciada)
	if obj.disputa_finalizada.is_connected(_on_disputa_finalizada):
		obj.disputa_finalizada.disconnect(_on_disputa_finalizada)

func _on_disputa_iniciada(obj: ObjetoAgarrable) -> void:
	if objeto_agarrado == obj:
		_en_disputa_activa = true

func _on_disputa_finalizada(ganador_id: int) -> void:
	_en_disputa_activa = false
	if ganador_id != multiplayer.get_unique_id():
		limpiar_estado_local()
