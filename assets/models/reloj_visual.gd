extends Node3D

@export_group("Referencias")
# Referencia actualizada al nuevo nombre de clase
@export var sistema_tiempo: ControladorTiempo 
@export var mesh_cara_reloj: MeshInstance3D
@export var pivote_agujas: Node3D

@export_group("Configuración")
@export var forzar_duracion_aqui: bool = false
@export var duracion_deseada_minutos: float = 3.0

var _ultimo_progreso_impreso: float = -1.0

func _ready() -> void:
	print("--- [RELOJ] INICIANDO _READY ---")

	# 1. BÚSQUEDA ROBUSTA (POR GRUPOS)
	if not sistema_tiempo:
		print("[RELOJ] Buscando 'proveedor_tiempo' en el árbol de grupos...")
		var nodo = get_tree().get_first_node_in_group("proveedor_tiempo")
		
		if nodo:
			# Intentamos convertir al nuevo tipo
			sistema_tiempo = nodo as ControladorTiempo
			
			if sistema_tiempo:
				print("[RELOJ] ✅ ¡ENCONTRADO! Conectado a: ", sistema_tiempo.name)
			else:
				print("[RELOJ] ⚠️ Encontré un nodo en el grupo, pero hubo error de tipos. Asignando forzosamente.")
				sistema_tiempo = nodo 
		else:
			print("[RELOJ] ⚠️ No encontrado por grupo. Probando búsqueda clásica por nombre...")
			sistema_tiempo = get_tree().root.find_child("SistemaTiempo", true, false)

	# 2. DIAGNÓSTICO FINAL DE REFERENCIA
	if not sistema_tiempo:
		printerr("[RELOJ] ❌ ERROR FATAL: No encuentro el SistemaTiempo (ControladorTiempo).")
		set_process(false)
		return
	
	# 3. CONFIGURACIÓN DE DURACIÓN (Solo Servidor)
	if forzar_duracion_aqui and multiplayer.is_server():
		sistema_tiempo.duracion_jornada = duracion_deseada_minutos * 60.0
		sistema_tiempo.tiempo_restante = sistema_tiempo.duracion_jornada
		print("[RELOJ] Configuración de tiempo forzada aplicada: ", duracion_deseada_minutos, " min.")

	# 4. CONFIGURACIÓN DE MATERIAL
	if mesh_cara_reloj:
		# get_active_material busca primero en el override, luego en la malla
		var mat = mesh_cara_reloj.get_active_material(0)
		if mat:
			if mat is ShaderMaterial:
				# Si no es Local to Scene, lo duplicamos para evitar bugs
				if not mat.resource_local_to_scene:
					var mat_unico = mat.duplicate()
					mesh_cara_reloj.set_surface_override_material(0, mat_unico)
					print("[RELOJ] Material duplicado por seguridad.")
				else:
					print("[RELOJ] Material es Local to Scene. Correcto.")
			else:
				printerr("[RELOJ] ❌ El material asignado no es un ShaderMaterial.")
		else:
			printerr("[RELOJ] ❌ No hay material en la cara del reloj.")
	else:
		printerr("[RELOJ] ❌ Falta asignar el nodo 'Mesh Cara Reloj' en el inspector.")

func _process(_delta: float) -> void:
	# Si llegamos aquí, sistema_tiempo existe
	
	var total = sistema_tiempo.duracion_jornada
	var actual = sistema_tiempo.tiempo_restante
	
	# Protección matemáticas
	if total <= 0: total = 0.001 
	
	# Cálculo de progreso (1.0 = rojo lleno, 0.0 = vacío)
	# Invertimos la lógica: empieza vacío (tiempo restante = total) y se llena
	var progreso = 1.0 - (actual / total)
	progreso = clamp(progreso, 0.0, 1.0)
	
	# DEBUG VISUAL (Solo imprime si cambia el progreso visiblemente)
	if abs(progreso - _ultimo_progreso_impreso) > 0.05:
		print("[RELOJ] TICK - Progreso: %.2f | Tiempo restante: %.1f" % [progreso, actual])
		_ultimo_progreso_impreso = progreso

	# 1. ACTUALIZAR SHADER (Rastro rojo)
	if mesh_cara_reloj:
		var mat = mesh_cara_reloj.get_active_material(0) as ShaderMaterial
		if mat:
			mat.set_shader_parameter("progreso", progreso)
	
	# 2. ACTUALIZAR AGUJA (Rotación)
	if pivote_agujas:
		# Sentido horario = rotación negativa en Z
		pivote_agujas.rotation_degrees.z = -360.0 * progreso
