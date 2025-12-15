extends Node3D

# --- CONFIGURACIÓN ---
@export var es_mano_izquierda: bool = false
@export var fuerza_lanzamiento: float = 6.0
@export var fuerza_lanzamiento_maxima: float = 20.0
@export var offset_reposo_cuerpo: Vector3 = Vector3(0.4, 1.0, -0.6)

@export_group("Tiempos")
@export var tiempo_para_lanzar: float = 0.3 
@export var tiempo_carga_maxima: float = 2.0 
@export var tiempo_limite_caida: float = 3.0 

# --- REFERENCIAS ---
@onready var mesh: MeshInstance3D = $MeshMano
@onready var pos_accion: Marker3D = $PosicionAccion
@onready var jugador_padre: Node3D = get_parent().get_parent()

var barra_carga_ui: ProgressBar = null 

# --- ESTADO GENERAL ---
var objeto_agarrado: RigidBody3D = null
var _tiempo_pulsado: float = 0.0
var _esta_pulsando: bool = false
var _ignorar_input_soltar: bool = false
var _modo_manosear: bool = false
var _punto_agarre_local: Vector3 = Vector3.ZERO
var _en_disputa_activa: bool = false
var _tiempo_desde_agarre: float = 0.0
var _z_original_accion: float = 0.0 
var _tween_activo: Tween

# --- ESTADO COLOCACIÓN ---
var _modo_colocacion: bool = false
var _estaba_colocando_input: bool = false # Para detectar flancos (Press/Release)
var _colocacion_cancelada: bool = false
var _fantasma_visual: MeshInstance3D = null
var _material_fantasma: StandardMaterial3D = null
var _posicion_fantasma_final: Vector3
var _rotacion_fantasma_final: Vector3

# Ángulo máximo de inclinación permitido (45 grados = solo suelos y rampas suaves)
const ANGULO_MAXIMO_SUELO: float = 45.0

func _ready() -> void:
	_z_original_accion = pos_accion.position.z
	
	# Material Rojo Brillante (Unshaded)
	_material_fantasma = StandardMaterial3D.new()
	_material_fantasma.albedo_color = Color(1, 0, 0, 0.6)
	_material_fantasma.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material_fantasma.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material_fantasma.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED 
	
	await get_tree().process_frame
	if jugador_padre:
		_actualizar_visuales(0.0)

func _physics_process(delta: float) -> void:
	# Barra de carga (Ocultar si colocamos)
	if _esta_pulsando and objeto_agarrado and not _ignorar_input_soltar and not _modo_colocacion:
		_tiempo_pulsado += delta
		if _tiempo_pulsado >= tiempo_limite_caida:
			print("[MANO] ¡Se te resbaló!")
			soltar(false)
			_resetear_input()
		else:
			_actualizar_barra_ui()
	else:
		_ocultar_barra_ui()

	# Gestión Objeto Agarrado
	if objeto_agarrado:
		_tiempo_desde_agarre += delta
		if _tiempo_desde_agarre > 0.5 and not _en_disputa_activa:
			if is_instance_valid(objeto_agarrado) and objeto_agarrado.get("id_sostenedor_1") != multiplayer.get_unique_id():
				limpiar_estado_local()
		
		# Siempre enviamos datos físicos para mantener el objeto en la mano hasta confirmar
		if is_instance_valid(objeto_agarrado):
			_enviar_datos_fisicos()
	
	_actualizar_visuales(delta)

func _actualizar_visuales(delta: float) -> void:
	var destino: Vector3

	if objeto_agarrado and is_instance_valid(objeto_agarrado):
		destino = objeto_agarrado.to_global(_punto_agarre_local)
		var dist_sq = mesh.global_position.distance_squared_to(destino)
		
		if dist_sq > 2.25 or dist_sq < 0.0001:
			mesh.global_position = destino
			mesh.rotation = objeto_agarrado.global_rotation
		else:
			mesh.global_position = mesh.global_position.lerp(destino, delta * 40.0)
			var dir = (destino - mesh.global_position).normalized()
			if not dir.is_zero_approx() and abs(dir.dot(Vector3.UP)) < 0.99:
				mesh.look_at(destino, Vector3.UP)
			
	elif _modo_manosear:
		destino = pos_accion.global_position
		_interpolar_reposo(destino, pos_accion.global_rotation, delta)
	else:
		if jugador_padre:
			var offset_final = offset_reposo_cuerpo
			offset_final.x = -abs(offset_final.x) if es_mano_izquierda else abs(offset_final.x)
			destino = jugador_padre.to_global(offset_final)
			_interpolar_reposo(destino, jugador_padre.global_rotation, delta)
		else:
			_interpolar_reposo(global_position, global_rotation, delta)

func _interpolar_reposo(dest: Vector3, rot_dest: Vector3, delta: float):
	mesh.global_position = mesh.global_position.lerp(dest, delta * 20.0)
	mesh.global_rotation.x = lerp_angle(mesh.global_rotation.x, rot_dest.x, delta * 15)
	mesh.global_rotation.y = lerp_angle(mesh.global_rotation.y, rot_dest.y, delta * 15)
	mesh.global_rotation.z = lerp_angle(mesh.global_rotation.z, rot_dest.z, delta * 15)

# --- INPUT (LÓGICA FINAL) ---
func gestionar_input(just_pressed: bool, is_pressed: bool, is_placing_held: bool, info: Dictionary) -> void:
	_esta_pulsando = is_pressed
	
	# Detectamos flancos de la tecla E (Colocar)
	var e_just_pressed = is_placing_held and not _estaba_colocando_input
	var e_just_released = not is_placing_held and _estaba_colocando_input
	_estaba_colocando_input = is_placing_held
	
	# --- MODO COLOCACIÓN ---
	if objeto_agarrado:
		
		# 1. EMPEZAR A COLOCAR (Pulsar E)
		if e_just_pressed:
			_iniciar_modo_colocacion()
		
		# 2. DURANTE LA COLOCACIÓN (Mantener E)
		if _modo_colocacion:
			# Si pulsamos Click Izquierdo -> CANCELAR
			if just_pressed:
				_colocacion_cancelada = true
				_limpiar_fantasma()
				print("[MANO] Colocación cancelada.")
				# Importante: No retornamos para que el click no cuente como disparo
				# sino que consumimos el evento aquí
			
			if not _colocacion_cancelada:
				_actualizar_fantasma(info)
		
		# 3. CONFIRMAR COLOCACIÓN (Soltar E)
		if e_just_released and _modo_colocacion:
			if not _colocacion_cancelada:
				# Solo ejecutamos si el fantasma es visible (sitio válido)
				if _fantasma_visual and _fantasma_visual.visible:
					_ejecutar_colocacion_suave()
			
			# Limpieza final
			_limpiar_fantasma()
			_modo_colocacion = false
			_colocacion_cancelada = false
	
	# Si estamos colocando (o acabamos de cancelar), bloqueamos el disparo normal
	if _modo_colocacion or _colocacion_cancelada: 
		return

	# --- MODO ACCIÓN (Click Normal, sin E) ---
	if just_pressed:
		_tiempo_pulsado = 0.0
		if not objeto_agarrado:
			if info.cuerpo:
				if info.cuerpo.has_method("interactuar"):
					info.cuerpo.interactuar()
					_modo_manosear = true
					_ignorar_input_soltar = true
				elif info.cuerpo is RigidBody3D:
					_intentar_agarrar(info.cuerpo, info.punto)
					_ignorar_input_soltar = true
			else:
				_modo_manosear = true
		else:
			_ignorar_input_soltar = false
	
	if is_pressed:
		if not objeto_agarrado and not _ignorar_input_soltar:
			_modo_manosear = true
	else:
		_modo_manosear = false 
		if not just_pressed: 
			if objeto_agarrado and not _ignorar_input_soltar:
				_decidir_accion_final()
			_ignorar_input_soltar = false
			_tiempo_pulsado = 0.0

# --- LÓGICA FANTASMA ---

func _iniciar_modo_colocacion():
	_modo_colocacion = true
	_colocacion_cancelada = false
	_ocultar_barra_ui()
	_limpiar_fantasma()
	
	var nodo_malla = _buscar_nodo_mesh(objeto_agarrado)
	if not nodo_malla:
		_colocacion_cancelada = true
		return
		
	_fantasma_visual = MeshInstance3D.new()
	get_tree().root.add_child(_fantasma_visual)
	
	_fantasma_visual.mesh = nodo_malla.mesh
	_fantasma_visual.scale = objeto_agarrado.scale * nodo_malla.scale
	
	for i in range(_fantasma_visual.mesh.get_surface_count()):
		_fantasma_visual.set_surface_override_material(i, _material_fantasma)

func _buscar_nodo_mesh(nodo_raiz: Node) -> MeshInstance3D:
	if "malla_normal" in nodo_raiz and nodo_raiz.malla_normal is MeshInstance3D:
		return nodo_raiz.malla_normal
	for hijo in nodo_raiz.get_children():
		if hijo is MeshInstance3D and hijo.visible: return hijo
		for nieto in hijo.get_children():
			if nieto is MeshInstance3D and nieto.visible: return nieto
	return null

func _actualizar_fantasma(info: Dictionary):
	if not _fantasma_visual: return
	
	var punto = info.get("punto", Vector3.ZERO)
	var normal = info.get("normal", Vector3.UP)
	
	# 1. Si no hay colisión, ocultar
	if punto == Vector3.ZERO:
		_fantasma_visual.visible = false
		return
	
	# 2. FILTRO DE SUPERFICIE HORIZONTAL
	# Calculamos el ángulo respecto a ARRIBA (Vector3.UP)
	var angulo = rad_to_deg(normal.angle_to(Vector3.UP))
	
	# Si la superficie está muy inclinada (> 45 grados), NO permitimos colocar
	if angulo > ANGULO_MAXIMO_SUELO:
		_fantasma_visual.visible = false
		return
	
	# Si llegamos aquí, es válido
	_fantasma_visual.visible = true
	_fantasma_visual.global_position = punto
	
	if normal.is_normalized() and not normal.is_zero_approx():
		_alinear_con_y(_fantasma_visual, normal)
	
	_posicion_fantasma_final = _fantasma_visual.global_position
	_rotacion_fantasma_final = _fantasma_visual.global_rotation

func _alinear_con_y(nodo: Node3D, nueva_y: Vector3):
	var z_original = nodo.global_transform.basis.z
	var x_nueva = nueva_y.cross(z_original).normalized()
	if x_nueva.is_zero_approx():
		x_nueva = nueva_y.cross(Vector3.RIGHT).normalized()
	var z_nueva = x_nueva.cross(nueva_y).normalized()
	nodo.global_transform.basis = Basis(x_nueva, nueva_y, z_nueva)

func _limpiar_fantasma():
	if _fantasma_visual:
		_fantasma_visual.queue_free()
		_fantasma_visual = null

func _ejecutar_colocacion_suave():
	if not objeto_agarrado: return
	
	objeto_agarrado.rpc("salir_de_bolsillo", _posicion_fantasma_final)
	objeto_agarrado.global_rotation = _rotacion_fantasma_final
	objeto_agarrado.linear_velocity = Vector3.ZERO
	objeto_agarrado.angular_velocity = Vector3.ZERO
	
	limpiar_estado_local()

# --- RESTO DE FUNCIONES ---
# _decidir_accion_final, _resetear_input, _animar_golpe_fisico, _animar_uso_suave, 
# forzar_agarre_inmediato, _intentar_agarrar, soltar, limpiar_estado_local, 
# _enviar_datos_fisicos, UI helpers, etc.

func _decidir_accion_final():
	if _tiempo_pulsado < tiempo_para_lanzar:
		if objeto_agarrado.has_method("usar_objeto"):
			objeto_agarrado.rpc("usar_objeto")
		if objeto_agarrado.get("usar_animacion_golpe"):
			var dist = objeto_agarrado.get("distancia_golpe")
			if dist == null: dist = 0.4
			_animar_golpe_fisico(dist)
		else:
			_animar_uso_suave()
	else:
		var rango = tiempo_carga_maxima - tiempo_para_lanzar
		var carga = clamp((_tiempo_pulsado - tiempo_para_lanzar) / rango, 0.0, 1.0)
		var fuerza = lerp(fuerza_lanzamiento, fuerza_lanzamiento_maxima, carga)
		soltar(true, fuerza)

func _resetear_input():
	_tiempo_pulsado = 0.0
	_esta_pulsando = false
	_ignorar_input_soltar = true
	_modo_manosear = false
	_ocultar_barra_ui()

func _animar_golpe_fisico(distancia: float):
	if _tween_activo and _tween_activo.is_valid(): _tween_activo.kill()
	_tween_activo = create_tween()
	_tween_activo.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if objeto_agarrado and objeto_agarrado.has_method("modificar_rigidez_temporal"):
		objeto_agarrado.rpc("modificar_rigidez_temporal", 10.0, 0.3)
	var distancia_reforzada = distancia * 1.5
	var objetivo_golpe = _z_original_accion - distancia_reforzada
	_tween_activo.tween_property(pos_accion, "position:z", objetivo_golpe, 0.1)
	_tween_activo.tween_property(pos_accion, "position:z", _z_original_accion, 0.2)

func _animar_uso_suave():
	if _tween_activo and _tween_activo.is_valid(): _tween_activo.kill()
	_tween_activo = create_tween()
	_tween_activo.tween_property(mesh, "position:z", -0.2, 0.05)
	_tween_activo.tween_property(mesh, "position:z", 0.0, 0.05)

func forzar_agarre_inmediato(cuerpo: RigidBody3D, posicion_mundo: Vector3) -> void:
	limpiar_estado_local()
	objeto_agarrado = cuerpo
	_punto_agarre_local = cuerpo.to_local(posicion_mundo)
	_tiempo_desde_agarre = 0.0
	_ignorar_input_soltar = true 
	if jugador_padre: jugador_padre.add_collision_exception_with(cuerpo)
	cuerpo.visible = true
	cuerpo.global_position = posicion_mundo
	if cuerpo.has_method("reset_physics_interpolation"): cuerpo.reset_physics_interpolation()
	mesh.global_position = posicion_mundo

func _intentar_agarrar(cuerpo: RigidBody3D, punto_impacto: Vector3) -> void:
	if cuerpo.has_method("intentar_coger"):
		_conectar_senales_disputa(cuerpo)
		cuerpo.rpc("intentar_coger", multiplayer.get_unique_id())
		objeto_agarrado = cuerpo
		_punto_agarre_local = cuerpo.to_local(punto_impacto)
		_tiempo_desde_agarre = 0.0
		if jugador_padre: jugador_padre.add_collision_exception_with(cuerpo)

func soltar(lanzar: bool, fuerza_custom: float = -1.0) -> void:
	if not objeto_agarrado: return
	var fuerza = fuerza_custom if fuerza_custom >= 0 else fuerza_lanzamiento
	var impulso = -pos_accion.global_transform.basis.z * fuerza if lanzar else Vector3.ZERO
	if objeto_agarrado.has_method("intentar_soltar"):
		objeto_agarrado.rpc("intentar_soltar", multiplayer.get_unique_id(), impulso)
	limpiar_estado_local()

func limpiar_estado_local() -> void:
	if objeto_agarrado:
		if jugador_padre: jugador_padre.remove_collision_exception_with(objeto_agarrado)
		_desconectar_senales_disputa(objeto_agarrado)
	objeto_agarrado = null
	_en_disputa_activa = false
	_punto_agarre_local = Vector3.ZERO
	_ocultar_barra_ui()

func _enviar_datos_fisicos() -> void:
	var offset_rotado = objeto_agarrado.global_transform.basis * _punto_agarre_local
	var pos_destino = pos_accion.global_position - offset_rotado
	var rot_destino = Quaternion(pos_accion.global_transform.basis.orthonormalized())
	objeto_agarrado.rpc("actualizar_objetivo_agarre", pos_destino, rot_destino, multiplayer.get_unique_id())

func _actualizar_barra_ui():
	if barra_carga_ui:
		barra_carga_ui.visible = true
		var porcentaje = (_tiempo_pulsado / tiempo_limite_caida) * 100.0
		barra_carga_ui.value = clamp(porcentaje, 0, 100)
		if _tiempo_pulsado < tiempo_para_lanzar: barra_carga_ui.modulate = Color.GREEN
		elif _tiempo_pulsado < tiempo_carga_maxima: barra_carga_ui.modulate = Color.YELLOW
		else: barra_carga_ui.modulate = Color.RED

func _ocultar_barra_ui():
	if barra_carga_ui and barra_carga_ui.visible:
		barra_carga_ui.visible = false
		barra_carga_ui.value = 0

func _conectar_senales_disputa(obj):
	if not obj.disputa_iniciada.is_connected(_on_disputa_iniciada):
		obj.disputa_iniciada.connect(_on_disputa_iniciada.bind(obj))
		obj.disputa_finalizada.connect(_on_disputa_finalizada)
func _desconectar_senales_disputa(obj):
	if is_instance_valid(obj):
		if obj.disputa_iniciada.is_connected(_on_disputa_iniciada): obj.disputa_iniciada.disconnect(_on_disputa_iniciada)
		if obj.disputa_finalizada.is_connected(_on_disputa_finalizada): obj.disputa_finalizada.disconnect(_on_disputa_finalizada)
func _on_disputa_iniciada(obj): if objeto_agarrado == obj: _en_disputa_activa = true
func _on_disputa_finalizada(ganador_id): 
	_en_disputa_activa = false
	if ganador_id != multiplayer.get_unique_id(): limpiar_estado_local()
