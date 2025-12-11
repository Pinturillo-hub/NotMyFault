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

# --- ESTADO ---
var objeto_agarrado: RigidBody3D = null
var _tiempo_pulsado: float = 0.0
var _esta_pulsando: bool = false
var _ignorar_input_soltar: bool = false
var _modo_manosear: bool = false
var _punto_agarre_local: Vector3 = Vector3.ZERO
var _en_disputa_activa: bool = false
var _tiempo_desde_agarre: float = 0.0
var _z_original_accion: float = 0.0 # Posición original del Marker3D

var _tween_activo: Tween

func _ready() -> void:
	# Guardar posición original del Marker3D para volver siempre ahí
	_z_original_accion = pos_accion.position.z

	# Inicialización visual
	await get_tree().process_frame
	if jugador_padre:
		_actualizar_visuales(0.0)

func _physics_process(delta: float) -> void:
	# Lógica Barra de Carga
	if _esta_pulsando and objeto_agarrado and not _ignorar_input_soltar:
		_tiempo_pulsado += delta
		if _tiempo_pulsado >= tiempo_limite_caida:
			print("[MANO] ¡Se te resbaló!")
			soltar(false)
			_resetear_input()
		else:
			_actualizar_barra_ui()
	else:
		_ocultar_barra_ui()

	# Gestión Objeto
	if objeto_agarrado:
		_tiempo_desde_agarre += delta
		if _tiempo_desde_agarre > 0.5 and not _en_disputa_activa:
			if is_instance_valid(objeto_agarrado) and objeto_agarrado.get("id_sostenedor_1") != multiplayer.get_unique_id():
				limpiar_estado_local()
		
		if is_instance_valid(objeto_agarrado):
			_enviar_datos_fisicos()
	
	_actualizar_visuales(delta)

# --- VISUALES Y MOVIMIENTO ---
func _actualizar_visuales(delta: float) -> void:
	# Si estamos en animación de golpe, dejamos que el Tween controle pos_accion
	# y la física controle el objeto. Nosotros solo pintamos la mano en el objeto.
	
	var destino: Vector3
	var rot_destino: Vector3
	
	if objeto_agarrado and is_instance_valid(objeto_agarrado):
		# MODO AGARRE: Seguir al objeto
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
		# MODO INTERACCIÓN VACÍA
		destino = pos_accion.global_position
		rot_destino = pos_accion.global_rotation
		_interpolar_reposo(destino, rot_destino, delta)
		
	else:
		# MODO REPOSO
		if jugador_padre:
			var offset_final = offset_reposo_cuerpo
			offset_final.x = -abs(offset_final.x) if es_mano_izquierda else abs(offset_final.x)
			
			destino = jugador_padre.to_global(offset_final)
			rot_destino = jugador_padre.global_rotation
		else:
			destino = global_position
			rot_destino = global_rotation
		
		_interpolar_reposo(destino, rot_destino, delta)

func _interpolar_reposo(dest: Vector3, rot_dest: Vector3, delta: float):
	mesh.global_position = mesh.global_position.lerp(dest, delta * 20.0)
	mesh.global_rotation.x = lerp_angle(mesh.global_rotation.x, rot_dest.x, delta * 15)
	mesh.global_rotation.y = lerp_angle(mesh.global_rotation.y, rot_dest.y, delta * 15)
	mesh.global_rotation.z = lerp_angle(mesh.global_rotation.z, rot_dest.z, delta * 15)

# --- INPUT ---
func gestionar_input(just_pressed: bool, is_pressed: bool, info: Dictionary) -> void:
	_esta_pulsando = is_pressed
	
	if just_pressed:
		_tiempo_pulsado = 0.0
		if not objeto_agarrado:
			# MANO VACÍA
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
			# MANO LLENA
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

func _decidir_accion_final():
	if _tiempo_pulsado < tiempo_para_lanzar:
		# USAR
		if objeto_agarrado.has_method("usar_objeto"):
			objeto_agarrado.rpc("usar_objeto")
		
		if objeto_agarrado.get("usar_animacion_golpe"):
			var dist = objeto_agarrado.get("distancia_golpe")
			if dist == null: dist = 0.4
			_animar_golpe_fisico(dist)
		else:
			_animar_uso_suave()
	else:
		# LANZAR
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

# --- ACCIONES FÍSICAS (AGARRE Y TWEEN CORREGIDO) ---

func _animar_golpe_fisico(distancia: float):
	if _tween_activo and _tween_activo.is_valid(): _tween_activo.kill()
	
	_tween_activo = create_tween()
	_tween_activo.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# 1. ENDURECER OBJETO (Importante para que no vibre)
	if objeto_agarrado and objeto_agarrado.has_method("modificar_rigidez_temporal"):
		objeto_agarrado.rpc("modificar_rigidez_temporal", 10.0, 0.3)
	
	# 2. CALCULAR OBJETIVO
	# Multiplicamos distancia para asegurar overshoot (que atraviese un poco)
	var distancia_reforzada = distancia * 1.5
	var objetivo_golpe = _z_original_accion - distancia_reforzada
	
	# 3. MOVER SOLO EL TARGET FÍSICO (pos_accion)
	# La malla (mesh) seguirá al objeto gracias a _actualizar_visuales
	_tween_activo.tween_property(pos_accion, "position:z", objetivo_golpe, 0.1)
	
	# 4. RETORNO A POSICIÓN ORIGINAL (No a 0.0)
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

# --- UI Y HELPERS ---
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
