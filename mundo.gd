extends Node3D

const VehiculoScript = preload("res://tren_seguidor.gd")

@onready var camara: Camera3D = $CamaraCenital
@onready var mapa_fondo: MeshInstance3D = $MapaFondo

var via_actual: Path3D = null
var modo_construccion: bool = true
var tipo_transporte_actual: String = "colectivo"
var modo_semaforo: bool = false
var modo_zonificacion_rci: bool = false

# Modos de Trazado y Desdoblamiento de 2 Carriles a 1 Mano
var exigir_regreso_a_deposito: bool = false
var estado_desdoble: int = 0 # 0 = Doble Mano, 1 = Rama Ida 1M, 2 = Rama Vuelta 1M
var punto_inicio_desdoble: Vector3 = Vector3.ZERO
var punto_fin_desdoble: Vector3 = Vector3.ZERO
var normal_inicio_desdoble: Vector3 = Vector3.RIGHT
var normal_fin_desdoble: Vector3 = Vector3.RIGHT
var tramos_konstruccion: Array[Dictionary] = []
var buffer_rama_ida: Array[Vector3] = []
var buffer_rama_vuelta: Array[Vector3] = []
var marcadores_nodos_desdoble: Array[Node3D] = []
var deposito_origen_actual: Node3D = null

@export var altura_via: float = 0.5 
@export var ancho_carril_individual: float = 1.15
@export var separacion_central_vias: float = 1.6

var rotacion_preview: float = 0.0
var malla_linea: MeshInstance3D = null
var contador_lineas: int = 0
var color_linea_actual: Color = Color.WHITE
var matiz_actual: float = 0.15

@export var intervalo_base_despacho: float = 16.0
@export var max_unidades_por_linea: int = 5

# Cámara Orbital
var objetivo_seguimiento: Node3D = null
var distancia_zoom_deseada: float = 45.0
var distancia_zoom_actual: float = 45.0
@export var zoom_seguimiento_min: float = 12.0
@export var zoom_seguimiento_max: float = 220.0
var angulo_orbital_h: float = 0.0
var angulo_orbital_v: float = -0.65
var arrastrando_orbita: bool = false
var ultima_pos_mouse: Vector2 = Vector2.ZERO

@export var color_asfalto: Color = Color("#bec5d8")
@export var tolerancia_color: float = 0.18
@export var radio_busqueda_snap: int = 35
var imagen_mapa: Image = null

# Reloj Urbano (velocidad_reloj = 0.05 -> 1 hora de juego cada 20 seg reales)
var hora_actual: float = 7.5 
@export var velocidad_reloj: float = 0.05 

# UI / HUD
var canvas_hud: CanvasLayer = null
var panel_telemetria: PanelContainer = null
var label_telemetria: RichTextLabel = null
var txt_cartelera_input: LineEdit = null
var txt_numero_input: LineEdit = null
var ventana_ayuda: Window = null
var ventana_edicion_linea: Window = null
var ventana_edificio: Window = null
var ventana_lista_lineas: Window = null
var ventana_rci: Window = null
var lbl_reloj_hud: Label = null
var btn_modo_recorrido: Button = null
var btn_desdoblar: Button = null

# Nodos de Infraestructura
var depositos_colectivos_nodos: Array[Node3D] = []
var depositos_premetro_nodos: Array[Node3D] = []
var centros_transbordo_nodos: Array[Node3D] = []
var flechas_conurbano_nodos: Array[Node3D] = []
var paradas_nodos: Array[Node3D] = []
var semaforos_nodos: Array[Node3D] = []
var radio_conexion_deposito: float = 32.0

var edificio_preview: Node3D = null
var tipo_edificio_a_colocar: String = ""
var linea_padre_para_ramal: Path3D = null

enum TipoRCI {
	RESIDENCIAL_BAJA,
	RESIDENCIAL_MEDIA,
	RESIDENCIAL_ALTA,
	COMERCIAL_BAJA,
	COMERCIAL_ALTA,
	OFICINAS,
	FINANCIERO,
	INDUSTRIAL,
	ESTATAL
}
var tipo_rci_seleccionado: TipoRCI = TipoRCI.RESIDENCIAL_MEDIA
var zonas_rci: Array[Dictionary] = []
var puntos_poligono_rci: Array[Vector3] = []
var malla_preview_rci: MeshInstance3D = null
var acumulador_tick_pasajeros: float = 0.0

func _ready() -> void:
	_cargar_imagen_mapa_para_snapping()
	_crear_interfaz_hud()
	
	malla_preview_rci = MeshInstance3D.new()
	malla_preview_rci.mesh = ImmediateMesh.new()
	var mat_rci = StandardMaterial3D.new()
	mat_rci.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_rci.albedo_color = Color(0.2, 1.0, 0.9, 0.8)
	malla_preview_rci.material_override = mat_rci
	add_child(malla_preview_rci)

func _cargar_imagen_mapa_para_snapping() -> void:
	var ruta_mapa: String = "res://Monochrome-1792204453038.png"
	if FileAccess.file_exists(ruta_mapa):
		imagen_mapa = Image.load_from_file(ruta_mapa)

func _generar_color_procedural() -> Color:
	matiz_actual = fmod(matiz_actual + 0.618033988749895, 1.0)
	return Color.from_hsv(matiz_actual, 0.88, 0.95)

func _process(delta: float) -> void:
	var delta_horas = delta * velocidad_reloj
	hora_actual = fmod(hora_actual + delta_horas, 24.0)
	_actualizar_reloj_en_pantalla()
	_actualizar_simulacion_demanda_rci(delta, delta_horas)

	var pto_mouse = _obtener_click_en_suelo(get_viewport().get_mouse_position())

	if edificio_preview != null and pto_mouse != null:
		edificio_preview.global_position = pto_mouse
		edificio_preview.rotation.y = rotacion_preview

	if modo_zonificacion_rci and pto_mouse != null:
		_dibujar_preview_poligono_rci(pto_mouse)

	if objetivo_seguimiento != null and is_instance_valid(objetivo_seguimiento):
		distancia_zoom_actual = lerp(distancia_zoom_actual, distancia_zoom_deseada, 10.0 * delta)
		var pos_objetivo: Vector3 = objetivo_seguimiento.global_position
		var offset_esferico = Vector3(
			sin(angulo_orbital_h) * cos(angulo_orbital_v),
			-sin(angulo_orbital_v),
			cos(angulo_orbital_h) * cos(angulo_orbital_v)
		) * distancia_zoom_actual
		
		camara.global_position = camara.global_position.lerp(pos_objetivo + offset_esferico, 9.0 * delta)
		camara.look_at(pos_objetivo + Vector3(0, 1.5, 0), Vector3.UP)
		_actualizar_telemetria_hud()
	else:
		if panel_telemetria != null and panel_telemetria.visible:
			panel_telemetria.visible = false

func _actualizar_reloj_en_pantalla() -> void:
	if lbl_reloj_hud != null:
		var h = int(hora_actual)
		var m = int((hora_actual - h) * 60.0)
		var fase = "Turno Noche"
		if hora_actual >= 6.0 and hora_actual < 11.0:
			fase = "Mañana (Salida Laboral)"
		elif hora_actual >= 11.0 and hora_actual < 16.5:
			fase = "Mediodía / Ocio Comercial"
		elif hora_actual >= 16.5 and hora_actual < 21.0:
			fase = "Tarde (Regreso a Casa + Ocio)"
		lbl_reloj_hud.text = "🕒 %02d:%02d hs | %s" % [h, m, fase]

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		if tipo_edificio_a_colocar != "":
			rotacion_preview += PI / 4.0
			return
		_abrir_panel_seleccion_rci()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		_alternar_menu_ayuda()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L:
		_alternar_lista_lineas()
		return

	if objetivo_seguimiento != null:
		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
				arrastrando_orbita = event.pressed
				ultima_pos_mouse = event.position
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				distancia_zoom_deseada = clamp(distancia_zoom_deseada - 6.0, zoom_seguimiento_min, zoom_seguimiento_max)
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				distancia_zoom_deseada = clamp(distancia_zoom_deseada + 6.0, zoom_seguimiento_min, zoom_seguimiento_max)
				return

		elif event is InputEventMouseMotion and arrastrando_orbita:
			var delta_mouse = event.position - ultima_pos_mouse
			ultima_pos_mouse = event.position
			angulo_orbital_h -= delta_mouse.x * 0.005
			angulo_orbital_v = clamp(angulo_orbital_v - delta_mouse.y * 0.005, -1.35, -0.15)
			return

		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			objetivo_seguimiento = null
			camara.rotation_degrees = Vector3(-60, 0, 0)
			return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I:
		var pto = _obtener_click_en_suelo(get_viewport().get_mouse_position())
		if pto != null:
			_intentar_inspeccionar_elemento(pto)
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		_alternar_desdoble_una_mano()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		tipo_transporte_actual = "premetro" if tipo_transporte_actual == "colectivo" else "colectivo"
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_D:
		if Input.is_key_pressed(KEY_SHIFT):
			_activar_modo_colocacion_edificio("deposito_premetro")
		else:
			_activar_modo_colocacion_edificio("deposito_bondi")
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		_activar_modo_colocacion_edificio("transbordo")
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		_activar_modo_colocacion_edificio("conurbano")
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_S:
		modo_semaforo = !modo_semaforo
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		var pto = _obtener_click_en_suelo(get_viewport().get_mouse_position())
		if pto != null:
			var l = _obtener_linea_cercana(pto)
			if l != null:
				_resaltar_linea_completa(l)
				_abrir_editor_ramal(l)
				return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Z:
		if modo_zonificacion_rci and puntos_poligono_rci.size() > 0:
			puntos_poligono_rci.pop_back()
		else:
			_deshacer_ultimo_punto()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		if modo_zonificacion_rci:
			modo_zonificacion_rci = false
			puntos_poligono_rci.clear()
			(malla_preview_rci.mesh as ImmediateMesh).clear_surfaces()
		else:
			_cancelar_linea_en_curso()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if tipo_edificio_a_colocar != "":
			tipo_edificio_a_colocar = ""
			if edificio_preview:
				edificio_preview.queue_free()
				edificio_preview = null
		return

	# Clic Izquierdo
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var punto_suelo = _obtener_click_en_suelo(event.position)
		if punto_suelo == null:
			return

		if tipo_edificio_a_colocar != "":
			if tipo_edificio_a_colocar == "deposito_bondi":
				_crear_deposito_colectivo(punto_suelo, rotacion_preview)
			elif tipo_edificio_a_colocar == "deposito_premetro":
				_crear_deposito_premetro(punto_suelo, rotacion_preview)
			elif tipo_edificio_a_colocar == "transbordo":
				_crear_centro_transbordo(punto_suelo, rotacion_preview)
			elif tipo_edificio_a_colocar == "conurbano":
				_crear_flecha_conurbano(punto_suelo, rotacion_preview)
			
			tipo_edificio_a_colocar = ""
			if edificio_preview:
				edificio_preview.queue_free()
				edificio_preview = null
			return

		if modo_zonificacion_rci:
			puntos_poligono_rci.append(punto_suelo)
			return

		if Input.is_key_pressed(KEY_J):
			if _intentar_borrar_estructura(punto_suelo):
				return

		if Input.is_key_pressed(KEY_K):
			if _intentar_borrar_semaforo(punto_suelo):
				return

		if modo_semaforo:
			if _intentar_agregar_semaforo_4_fases(punto_suelo):
				modo_semaforo = false
				return

		if Input.is_key_pressed(KEY_X):
			if _intentar_borrar_linea(punto_suelo):
				return

		if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_P):
			if _intentar_agregar_parada_a_linea_existente(punto_suelo):
				return

		var vehiculo = _detectar_colectivo_bajo_mouse(event.position)
		if vehiculo != null:
			objetivo_seguimiento = vehiculo
			panel_telemetria.visible = true
			if vehiculo.has_method("resaltar_recorrido"):
				vehiculo.resaltar_recorrido()
			return

		if via_actual == null:
			if _intentar_clickear_parada_o_semaforo(punto_suelo):
				return

		if modo_construccion:
			_procesar_punto_construccion(punto_suelo)

	# Enter o Espacio
	elif event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
		if modo_zonificacion_rci:
			if puntos_poligono_rci.size() > 2:
				get_viewport().set_input_as_handled()
				_confirmar_y_crear_poligono_rci()
		elif modo_construccion and via_actual != null:
			get_viewport().set_input_as_handled()
			_finalizar_linea_y_habilitar_frecuencia()

# --- DESDOBLAMIENTO EXACTO DE 2 CARRILES A 2 CALLES DE 1 MANO ---
func _obtener_normal_ultimo_tramo() -> Vector3:
	for i in range(tramos_konstruccion.size() - 1, -1, -1):
		var tr = tramos_konstruccion[i]
		if tr["tipo"] == "doble" and tr["puntos"].size() >= 2:
			var p2: Vector3 = tr["puntos"].back()
			var p1: Vector3 = tr["puntos"][tr["puntos"].size() - 2]
			var diff = p2 - p1
			if diff.length_squared() > 0.001:
				return Vector3.UP.cross(diff.normalized()).normalized()
	return Vector3.RIGHT

func _crear_marcador_nodo_carril(pos: Vector3, col: Color) -> void:
	if via_actual == null:
		return
	var esf = MeshInstance3D.new()
	var m = SphereMesh.new()
	m.radius = 0.85; m.height = 1.7
	esf.mesh = m
	esf.position = pos + Vector3(0, 0.35, 0)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	esf.material_override = mat
	via_actual.add_child(esf)
	marcadores_nodos_desdoble.append(esf)

func _limpiar_marcadores_desdoble() -> void:
	for m in marcadores_nodos_desdoble:
		if is_instance_valid(m):
			m.queue_free()
	marcadores_nodos_desdoble.clear()

func _alternar_desdoble_una_mano() -> void:
	if via_actual == null:
		print("⚠️ Primero iniciá una línea desde un depósito antes de desdoblar.")
		return
		
	if estado_desdoble == 0:
		var ult = _obtener_ultimo_punto_trazado()
		punto_inicio_desdoble = ult
		normal_inicio_desdoble = _obtener_normal_ultimo_tramo()
		
		# Crear los 2 nodos de separación (Carril Ida +separacion y Carril Vuelta -separacion)
		var nodo_ida_inicio = punto_inicio_desdoble - normal_inicio_desdoble * separacion_central_vias
		var nodo_vuelta_inicio = punto_inicio_desdoble + normal_inicio_desdoble * separacion_central_vias
		_crear_marcador_nodo_carril(nodo_ida_inicio, Color(0.2, 1.0, 0.4))
		_crear_marcador_nodo_carril(nodo_vuelta_inicio, Color(1.0, 0.5, 0.1))
		
		buffer_rama_ida.clear()
		buffer_rama_ida.append(nodo_ida_inicio)
		buffer_rama_vuelta.clear()
		estado_desdoble = 1
		if btn_desdoblar:
			btn_desdoblar.text = "🔀 Fin IDA 1M -> Pasar a VUELTA (V)"
		print("🔀 Bifurcación abierta: Trazá la calle de IDA (nodo verde) y tocá 'V' donde vuelva a hacerse doble mano.")
		
	elif estado_desdoble == 1:
		if buffer_rama_ida.size() < 2:
			print("⚠️ Marcá al menos una esquina en la rama de IDA antes de pasar a la VUELTA.")
			return
		punto_fin_desdoble = buffer_rama_ida.back()
		var p_prev = buffer_rama_ida[buffer_rama_ida.size() - 2]
		var diff_fin = punto_fin_desdoble - p_prev
		normal_fin_desdoble = Vector3.UP.cross(diff_fin.normalized()).normalized() if diff_fin.length_squared() > 0.001 else normal_inicio_desdoble
		
		# Ajustar el último punto de Ida al carril derecho del nodo de unión y crear el par de nodos de reencuentro
		var nodo_ida_fin = punto_fin_desdoble - normal_fin_desdoble * separacion_central_vias
		var nodo_vuelta_fin = punto_fin_desdoble + normal_fin_desdoble * separacion_central_vias
		buffer_rama_ida[buffer_rama_ida.size() - 1] = nodo_ida_fin
		_crear_marcador_nodo_carril(nodo_ida_fin, Color(0.2, 1.0, 0.4))
		_crear_marcador_nodo_carril(nodo_vuelta_fin, Color(1.0, 0.5, 0.1))
		
		buffer_rama_vuelta.clear()
		buffer_rama_vuelta.append(nodo_vuelta_fin)
		estado_desdoble = 2
		if btn_desdoblar:
			btn_desdoblar.text = "🔀 Unir VUELTA al inicio (V)"
		_reconstruir_curva_y_malla_actual()
		print("🔀 Ahora trazá la calle paralela de VUELTA (desde el nodo naranja) hasta volver al inicio del desdoble.")
		
	elif estado_desdoble == 2:
		var nodo_vuelta_inicio = punto_inicio_desdoble + normal_inicio_desdoble * separacion_central_vias
		buffer_rama_vuelta.append(nodo_vuelta_inicio)
		tramos_konstruccion.append({
			"tipo": "una_mano",
			"ida": buffer_rama_ida.duplicate(),
			"vuelta": buffer_rama_vuelta.duplicate()
		})
		tramos_konstruccion.append({
			"tipo": "doble",
			"puntos": [punto_fin_desdoble]
		})
		estado_desdoble = 0
		_limpiar_marcadores_desdoble()
		if btn_desdoblar:
			btn_desdoblar.text = "🔀 Desdoblar 1 Mano (V)"
		_reconstruir_curva_y_malla_actual()
		print("✅ Ambos carriles de 1 mano quedaron soldados al segmento doble.")

func _obtener_ultimo_punto_trazado() -> Vector3:
	if estado_desdoble == 1 and not buffer_rama_ida.is_empty():
		return buffer_rama_ida.back()
	elif estado_desdoble == 2 and not buffer_rama_vuelta.is_empty():
		return buffer_rama_vuelta.back()
	for i in range(tramos_konstruccion.size() - 1, -1, -1):
		var tr = tramos_konstruccion[i]
		if tr["tipo"] == "doble" and not tr["puntos"].is_empty():
			return tr["puntos"].back()
		elif tr["tipo"] == "una_mano" and not tr["ida"].is_empty():
			return tr["ida"].back()
	return Vector3.ZERO

func _activar_modo_colocacion_edificio(tipo: String) -> void:
	if edificio_preview != null:
		edificio_preview.queue_free()
		
	tipo_edificio_a_colocar = tipo
	rotacion_preview = 0.0
	
	edificio_preview = Node3D.new()
	var mat_fantasma = StandardMaterial3D.new()
	mat_fantasma.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_fantasma.albedo_color = Color(0.2, 0.85, 1.0, 0.55)
	mat_fantasma.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	if tipo == "deposito_bondi":
		box.size = Vector3(38, 7.5, 30)
	elif tipo == "deposito_premetro":
		box.size = Vector3(46, 9.0, 26)
	elif tipo == "transbordo":
		box.size = Vector3(44, 5.2, 10)
	elif tipo == "conurbano":
		box.size = Vector3(18, 4.0, 24)
		mat_fantasma.albedo_color = Color(1.0, 0.45, 0.1, 0.7)
		
	mesh_inst.mesh = box
	mesh_inst.position.y = box.size.y / 2.0
	mesh_inst.material_override = mat_fantasma
	edificio_preview.add_child(mesh_inst)
	
	var flecha = MeshInstance3D.new()
	var cil_f = CylinderMesh.new()
	cil_f.top_radius = 2.5; cil_f.bottom_radius = 2.5; cil_f.height = 0.3
	flecha.mesh = cil_f
	flecha.position = Vector3(0, 0.5, 10.0)
	var mat_f = StandardMaterial3D.new()
	mat_f.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_f.albedo_color = Color(1.0, 0.9, 0.1)
	flecha.material_override = mat_f
	edificio_preview.add_child(flecha)
	
	add_child(edificio_preview)

func _procesar_punto_construccion(punto_suelo: Vector3) -> void:
	if via_actual == null:
		var dep_nodo = _obtener_deposito_nodo_adecuado(punto_suelo, tipo_transporte_actual)
		if dep_nodo == null:
			print("⚠️ La línea debe iniciar haciendo clic en un Depósito (Tecla D).")
			return
		deposito_origen_actual = dep_nodo
		var pos_imantada: Vector3 = dep_nodo.get_meta("salida_magnetica", dep_nodo.global_position)
		_iniciar_nueva_linea(pos_imantada, tipo_transporte_actual)
		return

	if exigir_regreso_a_deposito and estado_desdoble == 0 and is_instance_valid(deposito_origen_actual):
		var pos_dep = deposito_origen_actual.get_meta("salida_magnetica", deposito_origen_actual.global_position)
		if punto_suelo.distance_to(deposito_origen_actual.global_position) <= radio_conexion_deposito and _contar_puntos_totales() >= 3:
			_agregar_punto_a_tramo_activo(pos_dep)
			via_actual.set_meta("conectado_a_terminal_final", true)
			_reconstruir_curva_y_malla_actual()
			print("🏁 Línea conectada de regreso a la Terminal. Ya podés presionar Espacio/Enter.")
			return

	var flecha_conurbano = _obtener_flecha_conurbano_cercana(punto_suelo)
	if flecha_conurbano != null and estado_desdoble == 0:
		var pos_flecha = flecha_conurbano.global_position + Vector3(0, altura_via, 0)
		_agregar_punto_a_tramo_activo(pos_flecha)
		_reconstruir_curva_y_malla_actual()
		via_actual.set_meta("sale_al_conurbano", true)
		via_actual.set_meta("pos_conurbano", pos_flecha)
		via_actual.set_meta("tiempo_conurbano_min", 90.0)
		return

	var transbordo_cercano = _obtener_transbordo_cercano(punto_suelo)
	if transbordo_cercano != null and not via_actual.has_meta("transbordo_" + str(transbordo_cercano.get_instance_id())):
		var lineas_mb: Array = transbordo_cercano.get_meta("lineas_conectadas", [])
		if lineas_mb.size() >= 6:
			print("⚠️ Este Metrobús ya tiene 6 líneas conectadas.")
			return
			
		var p_ent: Vector3 = transbordo_cercano.get_meta("entrada_magnetica")
		var p_cen: Vector3 = transbordo_cercano.global_position + Vector3(0, altura_via, 0)
		var p_sal: Vector3 = transbordo_cercano.get_meta("salida_magnetica")
		
		_agregar_punto_a_tramo_activo(p_ent)
		_agregar_punto_a_tramo_activo(p_cen)
		_agregar_punto_a_tramo_activo(p_sal)
		
		via_actual.set_meta("transbordo_" + str(transbordo_cercano.get_instance_id()), true)
		var pts_parada_mb: Array = via_actual.get_meta("puntos_parada_3d", [])
		pts_parada_mb.append(p_cen)
		via_actual.set_meta("puntos_parada_3d", pts_parada_mb)
		
		_registrar_linea_en_metrobus(transbordo_cercano, via_actual)
		_reconstruir_curva_y_malla_actual()
		return

	var punto_ajustado = _aplicar_snapping_calle(punto_suelo)
	if punto_ajustado != null:
		if estado_desdoble == 2 and punto_ajustado.distance_to(punto_inicio_desdoble) <= 24.0 and buffer_rama_vuelta.size() >= 2:
			_alternar_desdoble_una_mano()
			return
			
		var ult_pto = _obtener_ultimo_punto_trazado()
		if ult_pto.distance_to(punto_ajustado) < 0.8:
			return
		_agregar_punto_a_tramo_activo(punto_ajustado)
		_reconstruir_curva_y_malla_actual()

func _agregar_punto_a_tramo_activo(pto: Vector3) -> void:
	if estado_desdoble == 1:
		buffer_rama_ida.append(pto)
	elif estado_desdoble == 2:
		buffer_rama_vuelta.append(pto)
	else:
		if tramos_konstruccion.is_empty() or tramos_konstruccion.back()["tipo"] != "doble":
			tramos_konstruccion.append({"tipo": "doble", "puntos": [pto]})
		else:
			tramos_konstruccion.back()["puntos"].append(pto)

func _contar_puntos_totales() -> int:
	var c = 0
	for t in tramos_konstruccion:
		if t["tipo"] == "doble":
			c += t["puntos"].size()
		else:
			c += t["ida"].size() + t["vuelta"].size()
	return c

func _iniciar_nueva_linea(pos_inicio: Vector3, tipo: String) -> void:
	contador_lineas += 1
	via_actual = Path3D.new()
	via_actual.name = ("Premetro_" if tipo == "premetro" else "Linea_") + str(contador_lineas)
	via_actual.curve = Curve3D.new()
	via_actual.curve.bake_interval = 2.0
	via_actual.set_meta("tipo_transporte", tipo)
	via_actual.set_meta("paradas_metros", [] as Array[float])
	via_actual.set_meta("puntos_parada_3d", [] as Array[Vector3])
	via_actual.set_meta("semaforos", {} as Dictionary)
	via_actual.set_meta("indice_orden", contador_lineas)
	via_actual.set_meta("es_circuito_cerrado", true)
	via_actual.set_meta("conectado_a_terminal_final", false)
	via_actual.set_meta("tipo_cartelera", "digital")
	via_actual.set_meta("sale_al_conurbano", false)
	via_actual.set_meta("tiempo_conurbano_min", 90.0)
	
	estado_desdoble = 0
	_limpiar_marcadores_desdoble()
	buffer_rama_ida.clear()
	buffer_rama_vuelta.clear()
	tramos_konstruccion.clear()
	tramos_konstruccion.append({"tipo": "doble", "puntos": [pos_inicio]})
	
	if linea_padre_para_ramal != null:
		var col_padre: Color = linea_padre_para_ramal.get_meta("color_linea", Color.WHITE)
		color_linea_actual = col_padre.lightened(0.32)
		via_actual.set_meta("color_linea", color_linea_actual)
		via_actual.set_meta("numero_linea", linea_padre_para_ramal.get_meta("numero_linea", "100"))
		via_actual.set_meta("letra_ramal", "B")
		via_actual.set_meta("nombre_ramal", "Ramal B")
		via_actual.set_meta("cartelera_led", "X PARALELA")
		linea_padre_para_ramal = null
	else:
		if tipo == "premetro":
			color_linea_actual = Color("#b8bcc4")
			var color_ramal = _generar_color_procedural()
			via_actual.set_meta("color_linea", color_ramal)
			via_actual.set_meta("numero_linea", "P" + str(contador_lineas))
			via_actual.set_meta("letra_ramal", "A")
			via_actual.set_meta("nombre_ramal", "Ramal E2 - Centro Cívico")
			via_actual.set_meta("cartelera_led", "C. CÍVICO")
		else:
			color_linea_actual = _generar_color_procedural()
			via_actual.set_meta("color_linea", color_linea_actual)
			via_actual.set_meta("numero_linea", str(100 + contador_lineas))
			via_actual.set_meta("letra_ramal", "A")
			via_actual.set_meta("nombre_ramal", "Ramal A - Troncal")
			via_actual.set_meta("cartelera_led", "A CABECERA")

	add_child(via_actual)
	
	malla_linea = MeshInstance3D.new()
	malla_linea.name = "MallaCinta"
	malla_linea.mesh = ImmediateMesh.new()
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color_linea_actual
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	malla_linea.material_override = mat
	via_actual.add_child(malla_linea)
	via_actual.curve.add_point(pos_inicio)

# Construye la malla y la curva física de 2 carriles (Ida por carril derecho + Vuelta por carril opuesto)
func _reconstruir_curva_y_malla_actual() -> void:
	if via_actual == null or malla_linea == null:
		return
		
	var im: ImmediateMesh = malla_linea.mesh as ImmediateMesh
	im.clear_surfaces()
	
	var idx_linea: int = via_actual.get_meta("indice_orden", 1)
	var elevacion_capa: float = 0.15 + (idx_linea * 0.018)
	var mitad_ancho: float = ancho_carril_individual * 0.5
	var offset_mano: float = separacion_central_vias
	
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for tr in tramos_konstruccion:
		if tr["tipo"] == "doble":
			_dibujar_polilinea_en_malla(im, tr["puntos"], mitad_ancho, offset_mano, elevacion_capa, true)
		elif tr["tipo"] == "una_mano":
			_dibujar_polilinea_en_malla(im, tr["ida"], mitad_ancho, 0.0, elevacion_capa, false)
			_dibujar_polilinea_en_malla(im, tr["vuelta"], mitad_ancho, 0.0, elevacion_capa, false)
			
	if estado_desdoble >= 1 and buffer_rama_ida.size() >= 2:
		_dibujar_polilinea_en_malla(im, buffer_rama_ida, mitad_ancho, 0.0, elevacion_capa, false)
	if estado_desdoble == 2 and buffer_rama_vuelta.size() >= 2:
		_dibujar_polilinea_en_malla(im, buffer_rama_vuelta, mitad_ancho, 0.0, elevacion_capa, false)
	im.surface_end()
	
	# Armar la Curve3D desplazando cada tramo doble a su carril correspondiente para que el bondi gire en U al final y nunca vaya marcha atrás
	via_actual.curve.clear_points()
	
	# 1. Recorrido de IDA (tramos dobles desplazados a -normal * offset_mano, tramos 1M por su eje)
	for tr in tramos_konstruccion:
		if tr["tipo"] == "doble":
			var pts_carril_ida = _desplazar_polilinea_lateral(tr["puntos"], -offset_mano)
			for p in pts_carril_ida:
				_agregar_punto_curva_limpio(via_actual.curve, p)
		else:
			for p in tr["ida"]:
				_agregar_punto_curva_limpio(via_actual.curve, p)
				
	# 2. Recorrido de VUELTA (si no es Terminal a Terminal manual, regresa por el carril opuesto y por las ramas de vuelta)
	if not exigir_regreso_a_deposito:
		for idx in range(tramos_konstruccion.size() - 1, -1, -1):
			var tr = tramos_konstruccion[idx]
			if tr["tipo"] == "doble":
				var pts_inv: Array[Vector3] = []
				for j in range(tr["puntos"].size() - 1, -1, -1):
					pts_inv.append(tr["puntos"][j])
				var pts_carril_vuelta = _desplazar_polilinea_lateral(pts_inv, -offset_mano)
				for p in pts_carril_vuelta:
					_agregar_punto_curva_limpio(via_actual.curve, p)
			else:
				for p in tr["vuelta"]:
					_agregar_punto_curva_limpio(via_actual.curve, p)

func _desplazar_polilinea_lateral(pts: Array, offset_lat: float) -> Array[Vector3]:
	var res: Array[Vector3] = []
	if pts.is_empty():
		return res
	if pts.size() == 1:
		res.append(pts[0])
		return res
	for i in range(pts.size()):
		var dir = Vector3.FORWARD
		if i < pts.size() - 1:
			var d = pts[i + 1] - pts[i]
			if d.length_squared() > 0.001:
				dir = d.normalized()
		elif i > 0:
			var d = pts[i] - pts[i - 1]
			if d.length_squared() > 0.001:
				dir = d.normalized()
		var normal = Vector3.UP.cross(dir).normalized()
		res.append(pts[i] + normal * offset_lat)
	return res

func _agregar_punto_curva_limpio(curva: Curve3D, p: Vector3) -> void:
	if curva.point_count == 0 or curva.get_point_position(curva.point_count - 1).distance_to(p) > 0.4:
		curva.add_point(p)

func _dibujar_polilinea_en_malla(im: ImmediateMesh, pts: Array, mitad_ancho: float, offset_mano: float, elevacion: float, es_doble: bool) -> void:
	if pts.size() < 2:
		return
	var c_tmp = Curve3D.new()
	c_tmp.bake_interval = 2.0
	for p in pts:
		c_tmp.add_point(p)
	var baked = c_tmp.get_baked_points()
	var h = Vector3(0, elevacion, 0)
	
	for i in range(baked.size() - 1):
		var p1 = baked[i]
		var p2 = baked[i + 1]
		var diff = p2 - p1
		if diff.length_squared() < 0.001:
			continue
		var dir_t = diff.normalized()
		var normal_lat = Vector3.UP.cross(dir_t).normalized()
		
		if es_doble:
			for signo in [-1.0, 1.0]:
				var centro_carril = normal_lat * (signo * offset_mano)
				var b_izq = normal_lat * mitad_ancho
				var v1 = p1 + centro_carril - b_izq + h
				var v2 = p1 + centro_carril + b_izq + h
				var v3 = p2 + centro_carril + b_izq + h
				var v4 = p2 + centro_carril - b_izq + h
				im.surface_add_vertex(v1); im.surface_add_vertex(v2); im.surface_add_vertex(v3)
				im.surface_add_vertex(v1); im.surface_add_vertex(v3); im.surface_add_vertex(v4)
		else:
			var b_izq = normal_lat * mitad_ancho
			var v1 = p1 - b_izq + h
			var v2 = p1 + b_izq + h
			var v3 = p2 + b_izq + h
			var v4 = p2 - b_izq + h
			im.surface_add_vertex(v1); im.surface_add_vertex(v2); im.surface_add_vertex(v3)
			im.surface_add_vertex(v1); im.surface_add_vertex(v3); im.surface_add_vertex(v4)

func _resaltar_linea_completa(linea: Path3D) -> void:
	var malla = linea.get_node_or_null("MallaCinta") as MeshInstance3D
	if malla and malla.material_override:
		var mat = malla.material_override as StandardMaterial3D
		var col_orig: Color = linea.get_meta("color_linea", Color.WHITE)
		var tw = create_tween()
		tw.tween_property(mat, "albedo_color", Color.WHITE, 0.2)
		tw.tween_property(mat, "albedo_color", col_orig.lightened(0.4), 0.25)
		tw.tween_property(mat, "albedo_color", col_orig, 0.3)

# --- ESTACIÓN DE METROBÚS CABA PARA HASTA 6 LÍNEAS ---
func _crear_centro_transbordo(pos: Vector3, rot_y: float) -> void:
	var trans = Node3D.new()
	trans.position = pos
	trans.rotation.y = rot_y
	trans.add_to_group("centros_transbordo")
	
	var base = MeshInstance3D.new()
	var box_b = BoxMesh.new()
	box_b.size = Vector3(44.0, 0.45, 6.4)
	base.mesh = box_b
	base.position.y = 0.22
	var mat_b = StandardMaterial3D.new()
	mat_b.albedo_color = Color("#5a6065")
	base.material_override = mat_b
	trans.add_child(base)
	
	for z_borde in [-3.1, 3.1]:
		var borde_am = MeshInstance3D.new()
		var box_am = BoxMesh.new()
		box_am.size = Vector3(44.0, 0.48, 0.45)
		borde_am.mesh = box_am
		borde_am.position = Vector3(0, 0.23, z_borde)
		var mat_am = StandardMaterial3D.new()
		mat_am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat_am.albedo_color = Color("#f5b800")
		borde_am.material_override = mat_am
		trans.add_child(borde_am)
		
	var mat_estructura = StandardMaterial3D.new()
	mat_estructura.albedo_color = Color("#2b1d14")
	for x_col in [-18.0, -9.0, 0.0, 9.0, 18.0]:
		var pilar = MeshInstance3D.new()
		var box_pil = BoxMesh.new()
		box_pil.size = Vector3(0.45, 4.8, 0.45)
		pilar.mesh = box_pil
		pilar.position = Vector3(x_col, 2.6, -2.2)
		pilar.material_override = mat_estructura
		trans.add_child(pilar)
		
		var cesto = MeshInstance3D.new()
		var cil_c = CylinderMesh.new()
		cil_c.top_radius = 0.28; cil_c.bottom_radius = 0.28; cil_c.height = 0.9
		cesto.mesh = cil_c
		cesto.position = Vector3(x_col + 0.6, 1.0, -2.0)
		var mat_rojo = StandardMaterial3D.new()
		mat_rojo.albedo_color = Color("#d92b1c")
		cesto.material_override = mat_rojo
		trans.add_child(cesto)
		
	var techo = MeshInstance3D.new()
	var box_t = BoxMesh.new()
	box_t.size = Vector3(42.0, 0.28, 6.8)
	techo.mesh = box_t
	techo.position.y = 5.0
	var mat_t = StandardMaterial3D.new()
	mat_t.albedo_color = Color("#f2d98d")
	techo.material_override = mat_t
	trans.add_child(techo)
	
	for i in range(6):
		var x_bahia = -15.0 + (i * 6.0)
		var cartel_b = MeshInstance3D.new()
		cartel_b.name = "BahiaColor_" + str(i)
		var box_cb = BoxMesh.new()
		box_cb.size = Vector3(4.8, 0.75, 0.25)
		cartel_b.mesh = box_cb
		cartel_b.position = Vector3(x_bahia, 3.8, -2.1)
		var mat_cb = StandardMaterial3D.new()
		mat_cb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat_cb.albedo_color = Color("#333840")
		cartel_b.material_override = mat_cb
		trans.add_child(cartel_b)
		
		var lbl_b = Label3D.new()
		lbl_b.name = "BahiaTexto_" + str(i)
		lbl_b.text = "LIBRE"
		lbl_b.font_size = 32
		lbl_b.outline_size = 10
		lbl_b.position = Vector3(x_bahia, 3.8, -1.9)
		lbl_b.no_depth_test = true
		trans.add_child(lbl_b)
		
	var pad_entrada = MeshInstance3D.new()
	var cil_e = CylinderMesh.new()
	cil_e.top_radius = 1.8; cil_e.bottom_radius = 1.8; cil_e.height = 0.15
	pad_entrada.mesh = cil_e
	pad_entrada.position = Vector3(-23.0, 0.3, 0)
	var mat_e = StandardMaterial3D.new()
	mat_e.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_e.albedo_color = Color(0.1, 0.9, 0.2)
	pad_entrada.material_override = mat_e
	trans.add_child(pad_entrada)
	
	var pad_salida = MeshInstance3D.new()
	pad_salida.mesh = cil_e
	pad_salida.position = Vector3(23.0, 0.3, 0)
	var mat_s = StandardMaterial3D.new()
	mat_s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_s.albedo_color = Color(1.0, 0.5, 0.1)
	pad_salida.material_override = mat_s
	trans.add_child(pad_salida)
	
	var grupo_p = Node3D.new()
	grupo_p.name = "GrupoPersonas"
	trans.add_child(grupo_p)
	
	add_child(trans)
	trans.set_meta("distancia_entrada_local", Vector3(-23.0, 0, 0))
	trans.set_meta("distancia_salida_local", Vector3(23.0, 0, 0))
	trans.set_meta("tipo_instalacion", "Estación Metrobús (Máx. 6 Líneas)")
	trans.set_meta("lineas_conectadas", [] as Array)
	trans.set_meta("pasajeros_esperando", 0)
	_recalcular_salida_magnetica(trans)
	centros_transbordo_nodos.append(trans)

func _registrar_linea_en_metrobus(trans: Node3D, linea: Path3D) -> void:
	var lista: Array = trans.get_meta("lineas_conectadas", [])
	if lista.size() >= 6:
		return
	var idx = lista.size()
	var num = str(linea.get_meta("numero_linea", "100"))
	var col: Color = linea.get_meta("color_linea", Color.AZURE)
	lista.append({"numero": num, "color": col, "nodo": linea})
	trans.set_meta("lineas_conectadas", lista)
	
	var cartel_b = trans.get_node_or_null("BahiaColor_" + str(idx)) as MeshInstance3D
	if cartel_b and cartel_b.material_override:
		(cartel_b.material_override as StandardMaterial3D).albedo_color = col
	var lbl_b = trans.get_node_or_null("BahiaTexto_" + str(idx)) as Label3D
	if lbl_b:
		lbl_b.text = "LÍNEA " + num

# --- PÓRTICO VIAL AUTOPISTA SALIDA AL CONURBANO (SIN SUELO Y EDITABLE) ---
func _crear_flecha_conurbano(pos: Vector3, rot_y: float) -> void:
	var nodo_flecha = Node3D.new()
	nodo_flecha.position = pos
	nodo_flecha.rotation.y = rot_y
	nodo_flecha.add_to_group("flechas_conurbano")
	
	var mat_metal = StandardMaterial3D.new()
	mat_metal.albedo_color = Color("#b8bfc6")
	mat_metal.metallic = 0.6
	mat_metal.roughness = 0.35
	
	for lado_x in [-9.5, 9.5]:
		var columna = MeshInstance3D.new()
		var cil_v = CylinderMesh.new()
		cil_v.top_radius = 0.22; cil_v.bottom_radius = 0.26; cil_v.height = 7.2
		columna.mesh = cil_v
		columna.position = Vector3(lado_x, 3.6, 0)
		columna.material_override = mat_metal
		nodo_flecha.add_child(columna)
		
		var brazo = MeshInstance3D.new()
		var cil_h = CylinderMesh.new()
		cil_h.top_radius = 0.16; cil_h.bottom_radius = 0.16; cil_h.height = 3.2
		brazo.mesh = cil_h
		brazo.rotation_degrees.z = 90
		brazo.position = Vector3(lado_x - (1.4 * sign(lado_x)), 6.6, 0)
		brazo.material_override = mat_metal
		nodo_flecha.add_child(brazo)
	
	var marco_blanco = MeshInstance3D.new()
	var box_m = BoxMesh.new()
	box_m.size = Vector3(13.8, 4.4, 0.18)
	marco_blanco.mesh = box_m
	marco_blanco.position = Vector3(0, 6.6, 0)
	var mat_blanco = StandardMaterial3D.new()
	mat_blanco.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_blanco.albedo_color = Color("#f5f5f5")
	marco_blanco.material_override = mat_blanco
	nodo_flecha.add_child(marco_blanco)
	
	var chapa_verde = MeshInstance3D.new()
	var box_v = BoxMesh.new()
	box_v.size = Vector3(13.4, 4.0, 0.24)
	chapa_verde.mesh = box_v
	chapa_verde.position = Vector3(0, 6.6, 0)
	var mat_verde = StandardMaterial3D.new()
	mat_verde.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_verde.albedo_color = Color("#008f5a")
	chapa_verde.material_override = mat_verde
	nodo_flecha.add_child(chapa_verde)
	
	for div_x in [-2.2, 2.5]:
		var linea_div = MeshInstance3D.new()
		var box_d = BoxMesh.new()
		box_d.size = Vector3(0.1, 4.0, 0.28)
		linea_div.mesh = box_d
		linea_div.position = Vector3(div_x, 6.6, 0)
		linea_div.material_override = mat_blanco
		nodo_flecha.add_child(linea_div)
	
	var texto_inicial = "LUJÁN  |  SALIDA 400 m  |  MERCEDES\nBUENOS AIRES  |  S. A. DE GILES  |  NAVARRO\n⬇                ⬇                ⬇"
	var lbl = Label3D.new()
	lbl.name = "TextoCartelRuta"
	lbl.text = texto_inicial
	lbl.font_size = 34
	lbl.outline_size = 6
	lbl.outline_modulate = Color("#005c39")
	lbl.position = Vector3(0, 6.6, 0.16)
	lbl.modulate = Color.WHITE
	lbl.no_depth_test = true
	nodo_flecha.add_child(lbl)
	
	add_child(nodo_flecha)
	nodo_flecha.set_meta("tipo_instalacion", "Pórtico Salida al Conurbano")
	nodo_flecha.set_meta("texto_cartel", texto_inicial)
	flechas_conurbano_nodos.append(nodo_flecha)

func _obtener_flecha_conurbano_cercana(pos: Vector3):
	for f in flechas_conurbano_nodos:
		if is_instance_valid(f) and pos.distance_to(f.global_position) <= 28.0:
			return f
	return null

func _crear_deposito_colectivo(pos: Vector3, rot_y: float) -> void:
	var dep = Node3D.new()
	dep.position = pos
	dep.rotation.y = rot_y
	dep.add_to_group("depositos_colectivos")
	
	var piso = MeshInstance3D.new()
	var box_p = BoxMesh.new()
	box_p.size = Vector3(38.0, 0.4, 30.0)
	piso.mesh = box_p
	piso.position.y = 0.2
	var mat_p = StandardMaterial3D.new()
	mat_p.albedo_color = Color(0.24, 0.27, 0.3)
	piso.material_override = mat_p
	dep.add_child(piso)
	
	var galpon = MeshInstance3D.new()
	var box_g = BoxMesh.new()
	box_g.size = Vector3(32.0, 7.5, 18.0)
	galpon.mesh = box_g
	galpon.position = Vector3(0, 3.9, -5.0)
	var mat_g = StandardMaterial3D.new()
	mat_g.albedo_color = Color(0.16, 0.19, 0.23)
	galpon.material_override = mat_g
	dep.add_child(galpon)
	
	var borne = MeshInstance3D.new()
	var cil_b = CylinderMesh.new()
	cil_b.top_radius = 2.4; cil_b.bottom_radius = 2.4; cil_b.height = 0.15
	borne.mesh = cil_b
	borne.name = "BorneSalida"
	borne.position = Vector3(0, 0.35, 9.0)
	var mat_b = StandardMaterial3D.new()
	mat_b.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_b.albedo_color = Color(0.2, 0.85, 1.0)
	borne.material_override = mat_b
	dep.add_child(borne)
	
	add_child(dep)
	dep.set_meta("distancia_salida_local", Vector3(0, 0, 9.0))
	dep.set_meta("tipo_instalacion", "Depósito de Colectivos")
	_recalcular_salida_magnetica(dep)
	depositos_colectivos_nodos.append(dep)

func _crear_deposito_premetro(pos: Vector3, rot_y: float) -> void:
	var dep = Node3D.new()
	dep.position = pos
	dep.rotation.y = rot_y
	dep.add_to_group("depositos_premetro")
	
	var piso = MeshInstance3D.new()
	var box_p = BoxMesh.new()
	box_p.size = Vector3(46.0, 0.4, 26.0)
	piso.mesh = box_p
	piso.position.y = 0.2
	var mat_p = StandardMaterial3D.new()
	mat_p.albedo_color = Color(0.38, 0.36, 0.34)
	piso.material_override = mat_p
	dep.add_child(piso)
	
	var nave = MeshInstance3D.new()
	var box_n = BoxMesh.new()
	box_n.size = Vector3(40.0, 9.0, 16.0)
	nave.mesh = box_n
	nave.position = Vector3(0, 4.7, -4.0)
	var mat_n = StandardMaterial3D.new()
	mat_n.albedo_color = Color(0.14, 0.2, 0.28)
	nave.material_override = mat_n
	dep.add_child(nave)
	
	var borne = MeshInstance3D.new()
	var cil_b = CylinderMesh.new()
	cil_b.top_radius = 2.5; cil_b.bottom_radius = 2.5; cil_b.height = 0.15
	borne.mesh = cil_b
	borne.name = "BorneSalida"
	borne.position = Vector3(0, 0.35, 8.5)
	var mat_b = StandardMaterial3D.new()
	mat_b.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_b.albedo_color = Color(1.0, 0.82, 0.1)
	borne.material_override = mat_b
	dep.add_child(borne)
	
	add_child(dep)
	dep.set_meta("distancia_salida_local", Vector3(0, 0, 8.5))
	dep.set_meta("tipo_instalacion", "Depósito Ferroviario Premetro")
	_recalcular_salida_magnetica(dep)
	depositos_premetro_nodos.append(dep)

func _recalcular_salida_magnetica(nodo: Node3D) -> void:
	if not is_instance_valid(nodo) or not nodo.is_inside_tree():
		return
	var tr_trans: Transform3D = nodo.global_transform
	if nodo.has_meta("distancia_salida_local"):
		var loc_s: Vector3 = nodo.get_meta("distancia_salida_local")
		nodo.set_meta("salida_magnetica", tr_trans * loc_s)
	if nodo.has_meta("distancia_entrada_local"):
		var loc_e: Vector3 = nodo.get_meta("distancia_entrada_local")
		nodo.set_meta("entrada_magnetica", tr_trans * loc_e)

func _intentar_borrar_estructura(pos: Vector3) -> bool:
	for lista in [depositos_colectivos_nodos, depositos_premetro_nodos, centros_transbordo_nodos, flechas_conurbano_nodos, paradas_nodos]:
		for ed in lista:
			if is_instance_valid(ed) and ed.global_position.distance_to(pos) <= 24.0:
				lista.erase(ed)
				ed.queue_free()
				return true
	return false

func _intentar_inspeccionar_elemento(pos: Vector3) -> bool:
	if _intentar_clickear_parada_o_semaforo(pos):
		return true
	var todos = depositos_colectivos_nodos + depositos_premetro_nodos + centros_transbordo_nodos + flechas_conurbano_nodos
	for ed in todos:
		if is_instance_valid(ed) and ed.global_position.distance_to(pos) <= 22.0:
			_mostrar_panel_edificio_con_slider(ed)
			return true
	return false

func _intentar_clickear_parada_o_semaforo(pos: Vector3) -> bool:
	for sem in semaforos_nodos:
		if is_instance_valid(sem) and sem.global_position.distance_to(pos) <= 18.0:
			_abrir_editor_semaforo(sem)
			return true
	for p in paradas_nodos:
		if is_instance_valid(p) and p.global_position.distance_to(pos) <= 14.0:
			_mostrar_info_parada_o_metrobus(p, false)
			return true
	for mb in centros_transbordo_nodos:
		if is_instance_valid(mb) and mb.global_position.distance_to(pos) <= 22.0:
			_mostrar_info_parada_o_metrobus(mb, true)
			return true
	return false

func _mostrar_info_parada_o_metrobus(nodo: Node3D, es_metrobus: bool) -> void:
	if ventana_edificio != null and is_instance_valid(ventana_edificio):
		ventana_edificio.queue_free()
		
	ventana_edificio = Window.new()
	ventana_edificio.title = "Estación Metrobús" if es_metrobus else "Parada Oficial CABA"
	ventana_edificio.size = Vector2i(440, 340)
	ventana_edificio.position = Vector2i(650, 360)
	ventana_edificio.close_requested.connect(func(): ventana_edificio.queue_free())
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 18; vbox.offset_top = 18
	vbox.offset_right = -18; vbox.offset_bottom = -18
	
	var esperando = int(nodo.get_meta("pasajeros_esperando", 0))
	var personitas_visibles = int(ceil(float(esperando) / 5.0))
	
	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	
	var txt = "[font_size=20][b]%s[/b][/font_size]\n\n" % ("🚉 Centro de Transbordo Metrobús" if es_metrobus else "🚏 Parada de Colectivo CABA")
	txt += "[b]Pasajeros esperando ahora:[/b] [color=#ffcc00]%d pasajeros[/color]\n" % esperando
	txt += "[b]Representación visual:[/b] %d personitas 3D (1 persona = 5 pasajeros)\n\n" % personitas_visibles
	
	if es_metrobus:
		var l_con: Array = nodo.get_meta("lineas_conectadas", [])
		txt += "[b]Bahías ocupadas:[/b] %d / 6 líneas\n" % l_con.size()
		for item in l_con:
			txt += "• Línea %s\n" % item["numero"]
			
		vbox.add_child(rtl)
		var lbl_rot = Label.new()
		lbl_rot.text = "Rotar Estación Metrobús (0° a 360°):"
		vbox.add_child(lbl_rot)
		var sl = HSlider.new()
		sl.min_value = 0.0; sl.max_value = 360.0; sl.step = 5.0
		sl.value = rad_to_deg(nodo.rotation.y)
		sl.value_changed.connect(func(v: float):
			nodo.rotation.y = deg_to_rad(v)
			_recalcular_salida_magnetica(nodo)
		)
		vbox.add_child(sl)
	else:
		var num_l = str(nodo.get_meta("numero_linea", "100"))
		var letra_r = str(nodo.get_meta("letra_ramal", "A"))
		txt += "[b]Línea asignada:[/b] Línea %s (Ramal %s)\n" % [num_l, letra_r]
		vbox.add_child(rtl)
		
	rtl.text = txt
	var btn_ok = Button.new()
	btn_ok.text = "Cerrar"
	btn_ok.pressed.connect(func(): ventana_edificio.queue_free())
	vbox.add_child(btn_ok)
	
	ventana_edificio.add_child(vbox)
	canvas_hud.add_child(ventana_edificio)

func _mostrar_panel_edificio_con_slider(edificio: Node3D) -> void:
	if ventana_edificio != null and is_instance_valid(ventana_edificio):
		ventana_edificio.queue_free()
		
	var tipo = edificio.get_meta("tipo_instalacion", "Instalación")
	var lineas_asociadas: Array[String] = []
	var coches_activos: int = 0
	
	for hijo in get_children():
		if hijo is Path3D and hijo.curve and hijo.curve.point_count > 0:
			var p_inicio = hijo.curve.get_point_position(0)
			if p_inicio.distance_to(edificio.global_position) <= 35.0:
				var num = hijo.get_meta("numero_linea", "?")
				var ramal = hijo.get_meta("nombre_ramal", "Troncal")
				lineas_asociadas.append("• Línea %s (%s)" % [num, ramal])
				coches_activos += hijo.get_children().filter(func(n): return n is PathFollow3D).size()
				
	ventana_edificio = Window.new()
	ventana_edificio.title = "Gestión de " + tipo
	ventana_edificio.size = Vector2i(480, 460)
	ventana_edificio.position = Vector2i(650, 320)
	ventana_edificio.close_requested.connect(func(): ventana_edificio.queue_free())
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 18; vbox.offset_top = 18
	vbox.offset_right = -18; vbox.offset_bottom = -18
	
	var lbl_titulo = Label.new()
	lbl_titulo.text = "%s (Líneas: %d | Flota activa: %d)" % [tipo, lineas_asociadas.size(), coches_activos]
	vbox.add_child(lbl_titulo)
	vbox.add_child(HSeparator.new())
	
	var lbl_rot = Label.new()
	lbl_rot.text = "Orientación (0° a 360°):"
	vbox.add_child(lbl_rot)
	
	var slider_rot = HSlider.new()
	slider_rot.min_value = 0.0; slider_rot.max_value = 360.0; slider_rot.step = 5.0
	slider_rot.value = rad_to_deg(edificio.rotation.y)
	slider_rot.value_changed.connect(func(valor: float):
		edificio.rotation.y = deg_to_rad(valor)
		_recalcular_salida_magnetica(edificio)
	)
	vbox.add_child(slider_rot)
	
	var lbl_lineas = RichTextLabel.new()
	lbl_lineas.fit_content = true
	lbl_lineas.bbcode_enabled = true
	lbl_lineas.text = "\n[b]Líneas asignadas:[/b]\n" + ("\n".join(lineas_asociadas) if not lineas_asociadas.is_empty() else "[color=#888888]Sin líneas activas.[/color]")
	vbox.add_child(lbl_lineas)
	
	var lbl_cartel_3d = edificio.get_node_or_null("TextoCartelRuta") as Label3D
	if lbl_cartel_3d != null:
		vbox.add_child(HSeparator.new())
		var lbl_edit = Label.new()
		lbl_edit.text = "Editar texto del Pórtico Vial (usá | o saltos):"
		vbox.add_child(lbl_edit)
		
		var txt_cartel_ruta = TextEdit.new()
		txt_cartel_ruta.custom_minimum_size = Vector2(0, 85)
		txt_cartel_ruta.text = str(edificio.get_meta("texto_cartel", lbl_cartel_3d.text))
		txt_cartel_ruta.text_changed.connect(func():
			lbl_cartel_3d.text = txt_cartel_ruta.text.to_upper()
			edificio.set_meta("texto_cartel", txt_cartel_ruta.text.to_upper())
		)
		vbox.add_child(txt_cartel_ruta)
	
	var btn_cerrar = Button.new()
	btn_cerrar.text = "Listo"
	btn_cerrar.pressed.connect(func(): ventana_edificio.queue_free())
	vbox.add_child(btn_cerrar)
	
	ventana_edificio.add_child(vbox)
	canvas_hud.add_child(ventana_edificio)

func _obtener_deposito_nodo_adecuado(pos: Vector3, tipo: String):
	var lista = depositos_premetro_nodos if tipo == "premetro" else depositos_colectivos_nodos
	for dep in lista:
		if is_instance_valid(dep) and pos.distance_to(dep.global_position) <= radio_conexion_deposito:
			return dep
	return null

func _obtener_transbordo_cercano(pos: Vector3):
	for trans in centros_transbordo_nodos:
		if is_instance_valid(trans) and pos.distance_to(trans.global_position) <= 26.0:
			return trans
	return null

# --- POBLACIÓN FINITA POR VOLUMEN (M3 EN ESCALA 3000x3000) Y CICLO DE ESTADÍAS ---
func _calcular_area_poligono_m2(poly: PackedVector2Array) -> float:
	var n = poly.size()
	if n < 3:
		return 0.0
	var suma: float = 0.0
	for i in range(n):
		var p1 = poly[i]
		var p2 = poly[(i + 1) % n]
		suma += (p1.x * p2.y) - (p2.x * p1.y)
	return abs(suma) * 0.5

func _abrir_panel_seleccion_rci() -> void:
	if ventana_rci != null and is_instance_valid(ventana_rci):
		ventana_rci.queue_free()
		
	ventana_rci = Window.new()
	ventana_rci.title = "Seleccionar Zona RCI (Población por m³ y Estadía)"
	ventana_rci.size = Vector2i(450, 460)
	ventana_rci.position = Vector2i(680, 310)
	ventana_rci.close_requested.connect(func(): ventana_rci.queue_free())
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16; vbox.offset_top = 16
	vbox.offset_right = -16; vbox.offset_bottom = -16
	
	var lbl = Label.new()
	lbl.text = "Marcá varios puntos para delimitar la zona y presioná Enter:"
	vbox.add_child(lbl)
	
	var opciones = [
		["🟢 Residencial Baja (Casas - 8h estadía + Ocio)", TipoRCI.RESIDENCIAL_BAJA],
		["🟢 Residencial Media (Barrio - 8h estadía + Ocio)", TipoRCI.RESIDENCIAL_MEDIA],
		["🟢 Residencial Alta (Torres - 8h estadía + Ocio)", TipoRCI.RESIDENCIAL_ALTA],
		["🔵 Comercial Baja (Ocio/Compras 2 a 4 hs)", TipoRCI.COMERCIAL_BAJA],
		["🔵 Comercial Alta (Shoppings/Avenidas 2 a 4 hs)", TipoRCI.COMERCIAL_ALTA],
		["🔷 Oficinas Corporativas (Jornada 6 a 8 hs)", TipoRCI.OFICINAS],
		["💎 Distrito Financiero (Jornada 6 a 8 hs)", TipoRCI.FINANCIERO],
		["🟡 Industria / Logística (Jornadas 6-8h + Turno Noche)", TipoRCI.INDUSTRIAL],
		["🟣 Estatal / Universidades (Turnos 6 a 8 hs)", TipoRCI.ESTATAL]
	]
	
	for op in opciones:
		var btn = Button.new()
		btn.text = op[0]
		btn.pressed.connect(func():
			tipo_rci_seleccionado = op[1]
			modo_zonificacion_rci = true
			puntos_poligono_rci.clear()
			ventana_rci.queue_free()
		)
		vbox.add_child(btn)
		
	ventana_rci.add_child(vbox)
	canvas_hud.add_child(ventana_rci)

func _dibujar_preview_poligono_rci(mouse_pos: Vector3) -> void:
	var im: ImmediateMesh = malla_preview_rci.mesh as ImmediateMesh
	im.clear_surfaces()
	if puntos_poligono_rci.is_empty():
		return
	
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in puntos_poligono_rci:
		im.surface_add_vertex(p + Vector3(0, 0.25, 0))
	im.surface_add_vertex(mouse_pos + Vector3(0, 0.25, 0))
	im.surface_add_vertex(puntos_poligono_rci[0] + Vector3(0, 0.25, 0))
	im.surface_end()

func _confirmar_y_crear_poligono_rci() -> void:
	var poly2d = PackedVector2Array()
	var cx = 0.0
	var cz = 0.0
	for p in puntos_poligono_rci:
		poly2d.append(Vector2(p.x, p.z))
		cx += p.x
		cz += p.z
		
	cx /= puntos_poligono_rci.size()
	cz /= puntos_poligono_rci.size()
	var centro = Vector3(cx, 0.12, cz)
	
	var indices = Geometry2D.triangulate_polygon(poly2d)
	if indices.is_empty():
		puntos_poligono_rci.clear()
		(malla_preview_rci.mesh as ImmediateMesh).clear_surfaces()
		return

	# Cálculo de Volumen Edilicio (m³) y Población Delimitada acorde a mapa 3000x3000
	var area_m2: float = max(400.0, _calcular_area_poligono_m2(poly2d))
	var altura_media_m: float = 6.0
	var m3_por_persona: float = 180.0
	var estadia_min_hs: float = 6.0
	var estadia_max_hs: float = 8.0
	var col_zona = Color(0.2, 0.8, 0.2, 0.35)
	var nombre_zona = "Residencial"
	
	match tipo_rci_seleccionado:
		TipoRCI.RESIDENCIAL_BAJA:
			col_zona = Color(0.4, 0.85, 0.4, 0.32); nombre_zona = "Residencial Baja"
			altura_media_m = 4.5; m3_por_persona = 220.0; estadia_min_hs = 7.5; estadia_max_hs = 8.5
		TipoRCI.RESIDENCIAL_MEDIA:
			col_zona = Color(0.2, 0.75, 0.2, 0.38); nombre_zona = "Residencial Media"
			altura_media_m = 14.0; m3_por_persona = 160.0; estadia_min_hs = 7.5; estadia_max_hs = 8.5
		TipoRCI.RESIDENCIAL_ALTA:
			col_zona = Color(0.1, 0.6, 0.1, 0.44); nombre_zona = "Residencial Alta"
			altura_media_m = 36.0; m3_por_persona = 130.0; estadia_min_hs = 7.5; estadia_max_hs = 8.5
		TipoRCI.COMERCIAL_BAJA:
			col_zona = Color(0.3, 0.5, 0.9, 0.35); nombre_zona = "Comercial Baja"
			altura_media_m = 6.0; m3_por_persona = 190.0; estadia_min_hs = 2.0; estadia_max_hs = 4.0
		TipoRCI.COMERCIAL_ALTA:
			col_zona = Color(0.1, 0.3, 0.85, 0.42); nombre_zona = "Comercial Alta"
			altura_media_m = 18.0; m3_por_persona = 120.0; estadia_min_hs = 2.0; estadia_max_hs = 4.0
		TipoRCI.OFICINAS:
			col_zona = Color(0.1, 0.75, 0.85, 0.38); nombre_zona = "Oficinas"
			altura_media_m = 28.0; m3_por_persona = 140.0; estadia_min_hs = 6.0; estadia_max_hs = 8.0
		TipoRCI.FINANCIERO:
			col_zona = Color(0.2, 0.85, 1.0, 0.44); nombre_zona = "Distrito Financiero"
			altura_media_m = 45.0; m3_por_persona = 115.0; estadia_min_hs = 6.0; estadia_max_hs = 8.0
		TipoRCI.INDUSTRIAL:
			col_zona = Color(0.9, 0.75, 0.1, 0.35); nombre_zona = "Industrial"
			altura_media_m = 10.0; m3_por_persona = 210.0; estadia_min_hs = 6.0; estadia_max_hs = 8.0
		TipoRCI.ESTATAL:
			col_zona = Color(0.7, 0.2, 0.85, 0.38); nombre_zona = "Estatal / Universidad"
			altura_media_m = 16.0; m3_por_persona = 145.0; estadia_min_hs = 5.0; estadia_max_hs = 7.0

	var volumen_m3: float = area_m2 * altura_media_m
	var capacidad_personas: int = clamp(int(volumen_m3 / m3_por_persona), 25, 950)

	var malla_zona = MeshInstance3D.new()
	var im = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, indices.size(), 3):
		var v1 = puntos_poligono_rci[indices[i]] + Vector3(0, 0.12, 0)
		var v2 = puntos_poligono_rci[indices[i + 1]] + Vector3(0, 0.12, 0)
		var v3 = puntos_poligono_rci[indices[i + 2]] + Vector3(0, 0.12, 0)
		im.surface_add_vertex(v1); im.surface_add_vertex(v2); im.surface_add_vertex(v3)
	im.surface_end()
	malla_zona.mesh = im
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col_zona
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	malla_zona.material_override = mat
	
	var root_zona = Node3D.new()
	root_zona.add_child(malla_zona)
	
	var lbl = Label3D.new()
	lbl.font_size = 38
	lbl.outline_size = 12
	lbl.position = centro + Vector3(0, 4.5, 0)
	lbl.modulate = Color.WHITE
	root_zona.add_child(lbl)
	
	add_child(root_zona)
	
	# Crear cohortes iniciales con tiempos de estadía escalonados
	var es_res = tipo_rci_seleccionado in [TipoRCI.RESIDENCIAL_BAJA, TipoRCI.RESIDENCIAL_MEDIA, TipoRCI.RESIDENCIAL_ALTA]
	var adentro_inicial: int = capacidad_personas if es_res else int(capacidad_personas * 0.35)
	var grupos_estadia: Array[Dictionary] = []
	if adentro_inicial > 0:
		grupos_estadia.append({"cantidad": int(adentro_inicial * 0.5), "horas_restantes": randf_range(0.5, 2.5)})
		grupos_estadia.append({"cantidad": adentro_inicial - int(adentro_inicial * 0.5), "horas_restantes": randf_range(3.0, estadia_max_hs)})

	zonas_rci.append({
		"tipo": tipo_rci_seleccionado,
		"nombre": nombre_zona,
		"centro": centro,
		"volumen_m3": int(volumen_m3),
		"capacidad_max": capacidad_personas,
		"adentro_edificio": adentro_inicial,
		"grupos_estadia": grupos_estadia,
		"listos_para_salir": 0,
		"nivel_aburrimiento": 30.0,
		"estadia_min": estadia_min_hs,
		"estadia_max": estadia_max_hs,
		"nodo_visual": root_zona
	})
	
	modo_zonificacion_rci = false
	puntos_poligono_rci.clear()
	(malla_preview_rci.mesh as ImmediateMesh).clear_surfaces()

func _actualizar_simulacion_demanda_rci(dt: float, dt_horas: float) -> void:
	var es_manana = hora_actual >= 6.0 and hora_actual <= 10.5
	var es_horario_ocio = hora_actual >= 11.0 and hora_actual <= 20.5
	var es_turno_noche = hora_actual >= 20.5 or hora_actual < 5.5
	
	for z in zonas_rci:
		var es_residencial = z["tipo"] in [TipoRCI.RESIDENCIAL_BAJA, TipoRCI.RESIDENCIAL_MEDIA, TipoRCI.RESIDENCIAL_ALTA]
		var es_laboral = z["tipo"] in [TipoRCI.OFICINAS, TipoRCI.FINANCIERO, TipoRCI.INDUSTRIAL, TipoRCI.ESTATAL]
		var es_comercial = z["tipo"] in [TipoRCI.COMERCIAL_BAJA, TipoRCI.COMERCIAL_ALTA]
		
		# 1. Descontar horas de estadía a cada grupo adentro del edificio
		var grupos: Array = z["grupos_estadia"]
		var nuevos_grupos: Array[Dictionary] = []
		var total_adentro: int = 0
		
		for g in grupos:
			# En casas durante la mañana o en oficinas durante la tarde el reloj de salida corre más rápido
			var mult_reloj = 1.6 if (es_residencial and es_manana) or (es_laboral and hora_actual >= 16.5) else 1.0
			g["horas_restantes"] -= dt_horas * mult_reloj
			if g["horas_restantes"] <= 0.0:
				# Cumplieron sus 6-8h de trabajo, 8h en casa o 2-4h comerciales -> salen a buscar colectivo
				z["listos_para_salir"] = clamp(int(z["listos_para_salir"]) + int(g["cantidad"]), 0, int(z["capacidad_max"]))
			else:
				nuevos_grupos.append(g)
				total_adentro += int(g["cantidad"])
				
		# 2. Necesidad de Aburrimiento en Residenciales (dispara viajes de 2-4h a Comercial) y % Turno Noche
		if es_residencial and total_adentro > 4:
			z["nivel_aburrimiento"] = clamp(float(z["nivel_aburrimiento"]) + (dt_horas * 18.0), 0.0, 100.0)
			if es_horario_ocio and float(z["nivel_aburrimiento"]) >= 65.0 and not nuevos_grupos.is_empty():
				var salen_ocio = max(1, int(total_adentro * 0.12))
				nuevos_grupos[0]["cantidad"] = max(0, int(nuevos_grupos[0]["cantidad"]) - salen_ocio)
				total_adentro = max(0, total_adentro - salen_ocio)
				z["listos_para_salir"] = clamp(int(z["listos_para_salir"]) + salen_ocio, 0, int(z["capacidad_max"]))
				z["nivel_aburrimiento"] = 20.0
			elif es_turno_noche and randf() < (dt * 0.08) and not nuevos_grupos.is_empty():
				# Pequeño % nocturno que sale a trabajar de noche
				var salen_noche = max(1, int(total_adentro * 0.04))
				nuevos_grupos[0]["cantidad"] = max(0, int(nuevos_grupos[0]["cantidad"]) - salen_noche)
				total_adentro = max(0, total_adentro - salen_noche)
				z["listos_para_salir"] = clamp(int(z["listos_para_salir"]) + salen_noche, 0, int(z["capacidad_max"]))

		# Regeneración pasiva suave si el edificio quedó por debajo de su piso poblacional
		if total_adentro + int(z["listos_para_salir"]) < int(z["capacidad_max"] * 0.35):
			var recarga = max(1, int(z["capacidad_max"] * 0.15))
			nuevos_grupos.append({"cantidad": recarga, "horas_restantes": randf_range(z["estadia_min"], z["estadia_max"])})
			total_adentro += recarga

		z["grupos_estadia"] = nuevos_grupos
		z["adentro_edificio"] = total_adentro
		
		var nodo_vis: Node3D = z["nodo_visual"]
		if is_instance_valid(nodo_vis) and nodo_vis.get_child_count() > 1:
			var lbl: Label3D = nodo_vis.get_child(1) as Label3D
			if lbl:
				var txt_est = "%d-%dh" % [int(z["estadia_min"]), int(z["estadia_max"])]
				lbl.text = "%s (%d cap. x m³)\n🏢 %d en estadía (%s) | 🚶 %d saliendo" % [z["nombre"], z["capacidad_max"], total_adentro, txt_est, z["listos_para_salir"]]

	# Repartir únicamente la población real que salió de los edificios entre las paradas cercanas (sin crear gente infinita)
	acumulador_tick_pasajeros += dt
	if acumulador_tick_pasajeros >= 1.0:
		acumulador_tick_pasajeros = 0.0
		_distribuir_poblacion_a_paradas()

func _distribuir_poblacion_a_paradas() -> void:
	for z in zonas_rci:
		var disponibles: int = int(z["listos_para_salir"])
		if disponibles <= 0:
			continue
			
		# Buscar todas las paradas y estaciones de Metrobús dentro del radio de caminata (180m)
		var destinos_caminata: Array[Node3D] = []
		for p in paradas_nodos:
			if is_instance_valid(p) and p.global_position.distance_to(z["centro"]) <= 180.0:
				destinos_caminata.append(p)
		for mb in centros_transbordo_nodos:
			if is_instance_valid(mb) and mb.global_position.distance_to(z["centro"]) <= 210.0:
				destinos_caminata.append(mb)
				
		if destinos_caminata.is_empty():
			continue
			
		var por_parada: int = max(1, int(ceil(float(disponibles) / float(destinos_caminata.size()))))
		for nodo_p in destinos_caminata:
			if disponibles <= 0:
				break
			var es_mb = nodo_p.is_in_group("centros_transbordo")
			var tope_parada = 120 if es_mb else 65
			var esp_actual = int(nodo_p.get_meta("pasajeros_esperando", 0))
			var hueco_parada = max(0, tope_parada - esp_actual)
			if hueco_parada > 0:
				var pasan = min(disponibles, min(por_parada, hueco_parada))
				esp_actual += pasan
				disponibles -= pasan
				nodo_p.set_meta("pasajeros_esperando", esp_actual)
				_actualizar_personitas_3d(nodo_p, esp_actual, es_mb)
				
		z["listos_para_salir"] = disponibles

func _actualizar_personitas_3d(nodo_parada: Node3D, cantidad_pasajeros: int, es_metrobus: bool) -> void:
	var grupo = nodo_parada.get_node_or_null("GrupoPersonas") as Node3D
	if grupo == null:
		return
	var max_figuras: int = 16 if es_metrobus else 10
	var figuras_necesarias: int = clamp(int(ceil(float(cantidad_pasajeros) / 5.0)), 0, max_figuras)
	var actuales: int = grupo.get_child_count()
	
	while actuales < figuras_necesarias:
		var persona = _crear_personita_3d(actuales, es_metrobus)
		grupo.add_child(persona)
		actuales += 1
	while actuales > figuras_necesarias:
		var ult = grupo.get_child(actuales - 1)
		grupo.remove_child(ult)
		ult.queue_free()
		actuales -= 1

func _crear_personita_3d(indice: int, es_metrobus: bool) -> Node3D:
	var p_root = Node3D.new()
	if es_metrobus:
		var fila = indice / 8
		var col = indice % 8
		p_root.position = Vector3(-14.0 + col * 4.0, 0.45, -1.2 + fila * 1.6)
	else:
		var fila = indice / 5
		var col = indice % 5
		p_root.position = Vector3(-1.2 - col * 0.75, 0.0, -0.8 + fila * 0.85)
		
	var cuerpo = MeshInstance3D.new()
	var cil = CylinderMesh.new()
	cil.top_radius = 0.22; cil.bottom_radius = 0.25; cil.height = 1.15
	cuerpo.mesh = cil
	cuerpo.position.y = 0.58
	var mat_ropa = StandardMaterial3D.new()
	mat_ropa.albedo_color = Color.from_hsv(fmod(indice * 0.23, 1.0), 0.65, 0.85)
	cuerpo.material_override = mat_ropa
	p_root.add_child(cuerpo)
	
	var cabeza = MeshInstance3D.new()
	var esf = SphereMesh.new()
	esf.radius = 0.22; esf.height = 0.44
	cabeza.mesh = esf
	cabeza.position.y = 1.38
	var mat_piel = StandardMaterial3D.new()
	mat_piel.albedo_color = Color("#f2c29b")
	cabeza.material_override = mat_piel
	p_root.add_child(cabeza)
	return p_root

# Intercambio real: bajan a cumplir estadía en la zona RCI receptora y suben TODOS los que entren hasta 45
func procesar_intercambio_pasajeros_en_parada(pos_vehiculo: Vector3, pasajeros_actuales: int, capacidad_max: int) -> int:
	# 1. Calcular cuántos pasajeros bajan según las zonas RCI cercanas a esta parada y la hora actual
	var ratio_bajada: float = 0.2
	var zonas_destino: Array = []
	for z in zonas_rci:
		if pos_vehiculo.distance_to(z["centro"]) <= 190.0:
			zonas_destino.append(z)
			var es_res = z["tipo"] in [TipoRCI.RESIDENCIAL_BAJA, TipoRCI.RESIDENCIAL_MEDIA, TipoRCI.RESIDENCIAL_ALTA]
			var es_lab = z["tipo"] in [TipoRCI.OFICINAS, TipoRCI.FINANCIERO, TipoRCI.INDUSTRIAL, TipoRCI.ESTATAL]
			var es_com = z["tipo"] in [TipoRCI.COMERCIAL_BAJA, TipoRCI.COMERCIAL_ALTA]
			
			if es_lab and hora_actual >= 6.0 and hora_actual <= 11.5:
				ratio_bajada = max(ratio_bajada, 0.75) # Bajan en masa a trabajar 6-8 hs
			elif es_com and hora_actual >= 10.5 and hora_actual <= 20.5:
				ratio_bajada = max(ratio_bajada, 0.55) # Bajan a pasear/comprar 2-4 hs
			elif es_res and (hora_actual >= 16.0 or hora_actual < 6.0):
				ratio_bajada = max(ratio_bajada, 0.8)  # Bajan en sus casas a descansar 8 hs
			else:
				ratio_bajada = max(ratio_bajada, 0.35)

	var bajan: int = int(ceil(float(pasajeros_actuales) * ratio_bajada)) if pasajeros_actuales > 0 else 0
	bajan = clamp(bajan, 0, pasajeros_actuales)
	var quedan_arriba: int = pasajeros_actuales - bajan
	var asientos_libres: int = capacidad_max - quedan_arriba
	
	# Los que bajaron ingresan a las zonas RCI cercanas e inician su tiempo de estadía (6-8h trabajo, 2-4h comercial, 8h casa)
	if bajan > 0 and not zonas_destino.is_empty():
		var por_zona = max(1, int(ceil(float(bajan) / float(zonas_destino.size()))))
		var rest_bajan = bajan
		for z in zonas_destino:
			if rest_bajan <= 0:
				break
			var entran = min(rest_bajan, por_zona)
			rest_bajan -= entran
			var dur_estadia = randf_range(float(z["estadia_min"]), float(z["estadia_max"]))
			z["grupos_estadia"].append({"cantidad": entran, "horas_restantes": dur_estadia})
			z["adentro_edificio"] = int(z["adentro_edificio"]) + entran

	# 2. Subir a TODOS los pasajeros esperando en el Metrobús o Parada CABA hasta completar los 45 asientos
	for mb in centros_transbordo_nodos:
		if is_instance_valid(mb) and pos_vehiculo.distance_to(mb.global_position) <= 28.0:
			var esp_mb: int = int(mb.get_meta("pasajeros_esperando", 0))
			var suben_mb: int = min(esp_mb, asientos_libres) # Sube el 100% de lo que entre en el colectivo
			var nuevo_esp_mb: int = max(0, esp_mb - suben_mb)
			mb.set_meta("pasajeros_esperando", nuevo_esp_mb)
			_actualizar_personitas_3d(mb, nuevo_esp_mb, true)
			return clamp(quedan_arriba + suben_mb, 0, capacidad_max)
			
	var parada_cercana: Node3D = null
	var menor_d: float = 26.0
	for p in paradas_nodos:
		if is_instance_valid(p):
			var d = pos_vehiculo.distance_to(p.global_position)
			if d < menor_d:
				menor_d = d
				parada_cercana = p
				
	if parada_cercana != null:
		var esp_p: int = int(parada_cercana.get_meta("pasajeros_esperando", 0))
		var suben_p: int = min(esp_p, asientos_libres) # Sube todo lo que quepa sin límite artificial
		var nuevo_esp_p: int = max(0, esp_p - suben_p)
		parada_cercana.set_meta("pasajeros_esperando", nuevo_esp_p)
		_actualizar_personitas_3d(parada_cercana, nuevo_esp_p, false)
		return clamp(quedan_arriba + suben_p, 0, capacidad_max)
		
	return quedan_arriba

# --- SEMÁFOROS CABA AMARILLOS DE 3 ÓPTICAS, 2 POR LADO EN INTERSECCIÓN Y EDITABLES ---
func _intentar_agregar_semaforo_4_fases(pos_click: Vector3) -> bool:
	var lineas_en_cruce: Array[Path3D] = []
	for hijo in get_children():
		if hijo is Path3D and hijo != via_actual and hijo.curve:
			var pto_cercano = hijo.curve.get_closest_point(pos_click)
			if pos_click.distance_to(pto_cercano) <= 25.0:
				lineas_en_cruce.append(hijo)
	if lineas_en_cruce.is_empty():
		return false
	var pto_base = lineas_en_cruce[0].curve.get_closest_point(pos_click)
	_instalar_controlador_cruce(pto_base, lineas_en_cruce)
	return true

func _instalar_controlador_cruce(pos: Vector3, lineas: Array[Path3D]) -> void:
	var cruce_sem = Node3D.new()
	cruce_sem.position = pos
	cruce_sem.add_to_group("semaforos_cruce")
	cruce_sem.set_meta("duracion_fase_a", 10.0)
	cruce_sem.set_meta("duracion_fase_b", 10.0)
	cruce_sem.set_meta("lineas_cruce", lineas)
	
	var esquinas = [
		{"offset": Vector3(-5.2, 0, -5.2), "rot": 0.0, "grupo": "A"},
		{"offset": Vector3(5.2, 0, 5.2), "rot": 180.0, "grupo": "A"},
		{"offset": Vector3(5.2, 0, -5.2), "rot": 90.0, "grupo": "B"},
		{"offset": Vector3(-5.2, 0, 5.2), "rot": -90.0, "grupo": "B"}
	]
	
	var opticas_a: Array[Dictionary] = []
	var opticas_b: Array[Dictionary] = []
	
	for esq in esquinas:
		var datos_poste = _construir_poste_semaforo_caba(esq["offset"], esq["rot"])
		cruce_sem.add_child(datos_poste["nodo"])
		if esq["grupo"] == "A":
			opticas_a.append(datos_poste)
		else:
			opticas_b.append(datos_poste)
			
	var disco = MeshInstance3D.new()
	var c_d = CylinderMesh.new()
	c_d.top_radius = 6.5; c_d.bottom_radius = 6.5; c_d.height = 0.08
	disco.mesh = c_d
	disco.position.y = 0.05
	var mat_d = StandardMaterial3D.new()
	mat_d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_d.albedo_color = Color(0.1, 0.9, 0.1, 0.18)
	mat_d.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disco.material_override = mat_d
	cruce_sem.add_child(disco)

	for idx in range(lineas.size()):
		var l = lineas[idx]
		var off = l.curve.get_closest_offset(pos)
		if not l.has_meta("semaforos"):
			l.set_meta("semaforos", {})
		var d = l.get_meta("semaforos")
		d[off] = (idx % 2 == 1)
		l.set_meta("semaforos", d)

	var timer = Timer.new()
	timer.name = "TimerFase"
	timer.one_shot = false
	# Fase 0: A Verde / B Rojo | Fase 1: A Amarillo / B Rojo | Fase 2: A Rojo / B Verde | Fase 3: A Rojo / B Amarillo
	var estado = {"paso": 0}
	cruce_sem.set_meta("estado_interno", estado)
	
	var actualizar_luces = func(paso_actual: int):
		var col_a = "verde" if paso_actual == 0 else ("amarillo" if paso_actual == 1 else "rojo")
		var col_b = "verde" if paso_actual == 2 else ("amarillo" if paso_actual == 3 else "rojo")
		
		for op in opticas_a:
			_encender_optica_caba(op, col_a)
		for op in opticas_b:
			_encender_optica_caba(op, col_b)
			
		if paso_actual in [1, 3]:
			mat_d.albedo_color = Color(0.95, 0.8, 0.1, 0.24)
		elif paso_actual == 0:
			mat_d.albedo_color = Color(0.1, 0.9, 0.1, 0.18)
		else:
			mat_d.albedo_color = Color(0.95, 0.1, 0.1, 0.24)
		
		for idx in range(lineas.size()):
			var l = lineas[idx]
			if is_instance_valid(l) and l.has_meta("semaforos"):
				var off = l.curve.get_closest_offset(pos)
				var d = l.get_meta("semaforos")
				# Corta el paso si su calle está en rojo o ya entró en amarillo
				var corta_paso = (col_a != "verde") if (idx % 2 == 0) else (col_b != "verde")
				d[off] = corta_paso
				l.set_meta("semaforos", d)
				
	cruce_sem.set_meta("funcion_actualizar", actualizar_luces)
	
	timer.timeout.connect(func():
		estado["paso"] = (int(estado["paso"]) + 1) % 4
		var p = int(estado["paso"])
		actualizar_luces.call(p)
		
		# Con timer.start() obligamos a Godot a aplicar la duración exacta en este mismo instante
		if p == 0:
			timer.start(float(cruce_sem.get_meta("duracion_fase_a", 10.0)))
		elif p == 1 or p == 3:
			timer.start(1.4) # Amarillo de paso: 1.4 segundos reales
		elif p == 2:
			timer.start(float(cruce_sem.get_meta("duracion_fase_b", 10.0)))
	)
	cruce_sem.add_child(timer)
	add_child(cruce_sem)
	timer.start(float(cruce_sem.get_meta("duracion_fase_a", 10.0)))
	actualizar_luces.call(0)
	semaforos_nodos.append(cruce_sem)

func _construir_poste_semaforo_caba(pos_local: Vector3, rot_deg: float) -> Dictionary:
	var raiz = Node3D.new()
	raiz.position = pos_local
	raiz.rotation_degrees.y = rot_deg
	
	var mat_amarillo_caba = StandardMaterial3D.new()
	mat_amarillo_caba.albedo_color = Color("#f5b800")
	var mat_negro = StandardMaterial3D.new()
	mat_negro.albedo_color = Color("#141414")
	
	var poste = MeshInstance3D.new()
	var cil = CylinderMesh.new()
	cil.top_radius = 0.22; cil.bottom_radius = 0.26; cil.height = 6.2
	poste.mesh = cil
	poste.position.y = 3.1
	poste.material_override = mat_amarillo_caba
	raiz.add_child(poste)
	
	var cabezal = MeshInstance3D.new()
	var box_c = BoxMesh.new()
	box_c.size = Vector3(1.1, 2.7, 0.9)
	cabezal.mesh = box_c
	cabezal.position = Vector3(0, 5.0, 0.25)
	cabezal.material_override = mat_amarillo_caba
	raiz.add_child(cabezal)
	
	var frente = MeshInstance3D.new()
	var box_f = BoxMesh.new()
	box_f.size = Vector3(0.95, 2.55, 0.15)
	frente.mesh = box_f
	frente.position = Vector3(0, 5.0, 0.72)
	frente.material_override = mat_negro
	raiz.add_child(frente)
	
	var mat_r = _crear_material_optica(Color("#ff1a1a"), true)
	var mat_a = _crear_material_optica(Color("#ffcc00"), false)
	var mat_v = _crear_material_optica(Color("#1aff33"), false)
	
	var alturas = [5.8, 5.0, 4.2]
	var materiales = [mat_r, mat_a, mat_v]
	for i in range(3):
		var lente = MeshInstance3D.new()
		var esf = SphereMesh.new()
		esf.radius = 0.34; esf.height = 0.68
		lente.mesh = esf
		lente.position = Vector3(0, alturas[i], 0.82)
		lente.material_override = materiales[i]
		raiz.add_child(lente)
		
	return {"nodo": raiz, "mat_r": mat_r, "mat_a": mat_a, "mat_v": mat_v}

func _crear_material_optica(col: Color, encendida: bool) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col if encendida else col.darkened(0.82)
	m.emission_enabled = encendida
	m.emission = col
	m.emission_energy_multiplier = 4.0
	return m

func _encender_optica_caba(datos_op: Dictionary, color_activo: String) -> void:
	var mr: StandardMaterial3D = datos_op["mat_r"]
	var ma: StandardMaterial3D = datos_op["mat_a"]
	var mv: StandardMaterial3D = datos_op["mat_v"]
	
	var r_on = (color_activo == "rojo")
	var a_on = (color_activo == "amarillo")
	var v_on = (color_activo == "verde")
	
	mr.albedo_color = Color("#ff1a1a") if r_on else Color("#2b0808")
	mr.emission_enabled = r_on
	ma.albedo_color = Color("#ffcc00") if a_on else Color("#2b2205")
	ma.emission_enabled = a_on
	mv.albedo_color = Color("#1aff33") if v_on else Color("#062b0a")
	mv.emission_enabled = v_on

func _abrir_editor_semaforo(cruce_sem: Node3D) -> void:
	if ventana_edificio != null and is_instance_valid(ventana_edificio):
		ventana_edificio.queue_free()
		
	ventana_edificio = Window.new()
	ventana_edificio.title = "Configurar Fases del Semáforo CABA"
	ventana_edificio.size = Vector2i(440, 320)
	ventana_edificio.position = Vector2i(650, 360)
	ventana_edificio.close_requested.connect(func(): ventana_edificio.queue_free())
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 18; vbox.offset_top = 18
	vbox.offset_right = -18; vbox.offset_bottom = -18
	
	var dur_a = float(cruce_sem.get_meta("duracion_fase_a", 10.0))
	var dur_b = float(cruce_sem.get_meta("duracion_fase_b", 10.0))
	
	var lbl_a = Label.new()
	lbl_a.text = "Duración Verde Fase Principal (A): %d seg" % int(dur_a)
	vbox.add_child(lbl_a)
	var sl_a = HSlider.new()
	sl_a.min_value = 4.0; sl_a.max_value = 30.0; sl_a.step = 1.0; sl_a.value = dur_a
	sl_a.value_changed.connect(func(v: float):
		cruce_sem.set_meta("duracion_fase_a", v)
		lbl_a.text = "Duración Verde Fase Principal (A): %d seg" % int(v)
	)
	vbox.add_child(sl_a)
	
	var lbl_b = Label.new()
	lbl_b.text = "Duración Verde Fase Cruce (B): %d seg" % int(dur_b)
	vbox.add_child(lbl_b)
	var sl_b = HSlider.new()
	sl_b.min_value = 4.0; sl_b.max_value = 30.0; sl_b.step = 1.0; sl_b.value = dur_b
	sl_b.value_changed.connect(func(v: float):
		cruce_sem.set_meta("duracion_fase_b", v)
		lbl_b.text = "Duración Verde Fase Cruce (B): %d seg" % int(v)
	)
	vbox.add_child(sl_b)
	
	vbox.add_child(HSeparator.new())
	var btn_inv = Button.new()
	btn_inv.text = "🔄 Invertir Fase Ahora (Cambiar Verde/Rojo)"
	btn_inv.pressed.connect(func():
		var est: Dictionary = cruce_sem.get_meta("estado_interno")
		est["en_amarillo"] = false
		est["fase_a_verde"] = !est["fase_a_verde"]
		var fn: Callable = cruce_sem.get_meta("funcion_actualizar")
		fn.call(est["fase_a_verde"], false)
	)
	vbox.add_child(btn_inv)
	
	var btn_ok = Button.new()
	btn_ok.text = "Listo"
	btn_ok.pressed.connect(func(): ventana_edificio.queue_free())
	vbox.add_child(btn_ok)
	
	ventana_edificio.add_child(vbox)
	canvas_hud.add_child(ventana_edificio)

func _intentar_borrar_semaforo(pos: Vector3) -> bool:
	var semaforos = get_tree().get_nodes_in_group("semaforos_cruce")
	for s in semaforos:
		if is_instance_valid(s) and s.global_position.distance_to(pos) <= 18.0:
			for hijo in get_children():
				if hijo is Path3D and hijo.has_meta("semaforos"):
					var d = hijo.get_meta("semaforos")
					var off = hijo.curve.get_closest_offset(s.global_position)
					d.erase(off)
					hijo.set_meta("semaforos", d)
			semaforos_nodos.erase(s)
			s.queue_free()
			return true
	return false

func _finalizar_linea_y_habilitar_frecuencia() -> void:
	if via_actual == null or _contar_puntos_totales() < 2:
		return
	if estado_desdoble != 0:
		print("⚠️ Todavía tenés un tramo de 1 mano sin cerrar. Tocá 'V' para unirlo antes de inaugurar.")
		return
	if exigir_regreso_a_deposito and not via_actual.get_meta("conectado_a_terminal_final", false):
		print("⚠️ En modo 'Terminal a Terminal', tenés que volver y hacer clic en el Depósito de origen para cerrar la línea.")
		return

	_reconstruir_curva_y_malla_actual()
	_limpiar_marcadores_desdoble()
	
	var lista_paradas: Array = via_actual.get_meta("paradas_metros", [])
	var pts_mb: Array = via_actual.get_meta("puntos_parada_3d", [])
	for p_mb in pts_mb:
		var off_mb = via_actual.curve.get_closest_offset(p_mb)
		if not lista_paradas.has(off_mb):
			lista_paradas.append(off_mb)
	lista_paradas.sort()
	via_actual.set_meta("paradas_metros", lista_paradas)
	
	if via_actual.get_meta("sale_al_conurbano", false):
		var p_con: Vector3 = via_actual.get_meta("pos_conurbano")
		via_actual.set_meta("metro_conurbano", via_actual.curve.get_closest_offset(p_con))

	var linea_ref = via_actual
	_despachar_unidad(linea_ref)
	
	var timer = Timer.new()
	timer.wait_time = randf_range(intervalo_base_despacho - 2.0, intervalo_base_despacho + 8.0)
	timer.autostart = true
	timer.timeout.connect(func():
		if is_instance_valid(linea_ref):
			var flota = linea_ref.get_children().filter(func(n): return n is PathFollow3D).size()
			if flota < max_unidades_por_linea:
				_despachar_unidad(linea_ref)
				timer.wait_time = randf_range(intervalo_base_despacho - 2.0, intervalo_base_despacho + 8.0)
	)
	linea_ref.add_child(timer)
	via_actual = null
	malla_linea = null
	deposito_origen_actual = null

func _despachar_unidad(linea: Path3D) -> void:
	var seguidor: PathFollow3D = VehiculoScript.new()
	seguidor.loop = true
	seguidor.rotation_mode = PathFollow3D.ROTATION_Y
	seguidor.use_model_front = true
	seguidor.add_to_group("colectivos")
	
	var cant = linea.get_children().filter(func(n): return n is PathFollow3D).size() + 1
	var num = linea.get_meta("numero_linea", "100")
	var col: Color = linea.get_meta("color_linea", Color.AZURE)
	var tipo = linea.get_meta("tipo_transporte", "colectivo")
	var ramal_letra = linea.get_meta("letra_ramal", "A")
	
	seguidor.name = ("Premetro " if tipo == "premetro" else "Línea ") + str(num) + " - Ramal " + ramal_letra + " (Int. " + str(cant) + ")"
	
	if linea.has_meta("paradas_metros"):
		var p_ext: Array = linea.get_meta("paradas_metros")
		seguidor.set("paradas_metros", p_ext.duplicate())
	
	seguidor.set("velocidad_crucero", randf_range(11.5, 14.2) if tipo == "colectivo" else randf_range(13.0, 16.5))
	seguidor.set("aceleracion", randf_range(3.2, 4.4))
	seguidor.set("tiempo_espera_parada", randf_range(2.2, 4.5))
	
	linea.add_child(seguidor)
	
	if tipo == "premetro":
		_ensamblar_premetro_materfer(seguidor, col, num, linea.get_meta("cartelera_led", "C. CÍVICO"))
	else:
		_ensamblar_colectivo_redondeado(seguidor, col, num, ramal_letra, linea.get_meta("cartelera_led", "A CABECERA"))

func _ensamblar_colectivo_redondeado(seguidor: PathFollow3D, col_carroceria: Color, num_linea: String, _letra_ramal: String, texto_led: String) -> void:
	var cuerpo = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(2.5, 2.7, 11.5)
	cuerpo.mesh = box
	cuerpo.position.y = 1.6
	var mat_c = StandardMaterial3D.new()
	mat_c.albedo_color = col_carroceria
	cuerpo.material_override = mat_c
	seguidor.add_child(cuerpo)
	
	var techo = MeshInstance3D.new()
	var box_t = BoxMesh.new()
	box_t.size = Vector3(2.45, 0.45, 11.3)
	techo.mesh = box_t
	techo.position.y = 3.05
	var mat_t = StandardMaterial3D.new()
	mat_t.albedo_color = Color(0.96, 0.96, 0.96)
	techo.material_override = mat_t
	seguidor.add_child(techo)
	
	var vidrios = MeshInstance3D.new()
	var box_v = BoxMesh.new()
	box_v.size = Vector3(2.55, 0.95, 9.8)
	vidrios.mesh = box_v
	vidrios.position = Vector3(0, 2.05, -0.2)
	var mat_v = StandardMaterial3D.new()
	mat_v.albedo_color = Color(0.08, 0.1, 0.12)
	vidrios.material_override = mat_v
	seguidor.add_child(vidrios)
	
	var parabrisas = MeshInstance3D.new()
	var box_p = BoxMesh.new()
	box_p.size = Vector3(2.35, 1.05, 0.2)
	parabrisas.mesh = box_p
	parabrisas.position = Vector3(0, 2.05, 5.76)
	parabrisas.rotation_degrees.x = -10
	parabrisas.material_override = mat_v
	seguidor.add_child(parabrisas)
	
	var tipo_cartel: String = "digital"
	var linea_padre = seguidor.get_parent()
	if linea_padre != null and linea_padre.has_meta("tipo_cartelera"):
		tipo_cartel = linea_padre.get_meta("tipo_cartelera")
	
	var visor_caja = MeshInstance3D.new()
	visor_caja.name = "VisorCaja"
	var box_vl = BoxMesh.new()
	box_vl.size = Vector3(2.35, 0.58, 0.12)
	visor_caja.mesh = box_vl
	visor_caja.position = Vector3(0, 2.78, 5.78)
	var mat_vl = StandardMaterial3D.new()
	mat_vl.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_vl.albedo_color = Color("#080808") if tipo_cartel == "digital" else Color("#f2f2f2")
	visor_caja.material_override = mat_vl
	seguidor.add_child(visor_caja)
	
	var label_num = Label3D.new()
	label_num.name = "CartelNumero"
	label_num.text = num_linea
	label_num.font_size = 42
	label_num.outline_size = 12
	label_num.outline_modulate = Color.BLACK
	label_num.position = Vector3(-0.85, 2.78, 5.86)
	label_num.no_depth_test = true
	label_num.modulate = Color("#ffb300") if tipo_cartel == "digital" else Color("#111111")
	seguidor.add_child(label_num)
	
	var cartel_led = Label3D.new()
	cartel_led.name = "CartelLED"
	cartel_led.autowrap_mode = TextServer.AUTOWRAP_OFF
	cartel_led.width = 460.0
	cartel_led.font_size = 28 if tipo_cartel == "digital" else 22
	cartel_led.outline_size = 10 if tipo_cartel == "digital" else 0
	cartel_led.outline_modulate = Color.BLACK
	cartel_led.position = Vector3(0.28, 2.78, 5.86)
	cartel_led.no_depth_test = true
	
	if tipo_cartel == "digital":
		cartel_led.modulate = Color("#ffb300")
		cartel_led.text = texto_led.to_upper() + "   *   "
	else:
		cartel_led.modulate = Color("#111111")
		cartel_led.line_spacing = -4
		cartel_led.text = "RETIRO - ONCE\nPOMPEYA - PTE. LA NORIA"
	seguidor.add_child(cartel_led)
	
	_crear_luz_vehiculo(seguidor, Vector3(-0.9, 0.9, 5.8), Color(1.0, 1.0, 0.85), 3.5, Vector3(0.45, 0.3, 0.2))
	_crear_luz_vehiculo(seguidor, Vector3(0.9, 0.9, 5.8), Color(1.0, 1.0, 0.85), 3.5, Vector3(0.45, 0.3, 0.2))
	_crear_luz_vehiculo(seguidor, Vector3(-0.9, 1.1, -5.8), Color(0.95, 0.05, 0.05), 3.0, Vector3(0.4, 0.3, 0.2))
	_crear_luz_vehiculo(seguidor, Vector3(0.9, 1.1, -5.8), Color(0.95, 0.05, 0.05), 3.0, Vector3(0.4, 0.3, 0.2))

func _ensamblar_premetro_materfer(seguidor: PathFollow3D, col_tranvia: Color, num_linea: String, texto_led: String) -> void:
	var cuerpo = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(2.5, 2.8, 14.8)
	cuerpo.mesh = box
	cuerpo.position.y = 1.7
	var mat_m = StandardMaterial3D.new()
	mat_m.albedo_color = col_tranvia
	cuerpo.material_override = mat_m
	seguidor.add_child(cuerpo)
	
	var franja = MeshInstance3D.new()
	var box_f = BoxMesh.new()
	box_f.size = Vector3(2.54, 0.45, 14.9)
	franja.mesh = box_f
	franja.position = Vector3(0, 1.3, 0)
	var mat_fr = StandardMaterial3D.new()
	mat_fr.albedo_color = Color(0.15, 0.25, 0.4)
	franja.material_override = mat_fr
	seguidor.add_child(franja)
	
	for z_dir in [7.2, -7.2]:
		var cabina = MeshInstance3D.new()
		var cil_cab = CylinderMesh.new()
		cil_cab.top_radius = 1.25; cil_cab.bottom_radius = 1.25; cil_cab.height = 2.8
		cabina.mesh = cil_cab
		cabina.position = Vector3(0, 1.7, z_dir)
		cabina.material_override = mat_m
		seguidor.add_child(cabina)
	
	var techo = MeshInstance3D.new()
	var box_t = BoxMesh.new()
	box_t.size = Vector3(2.4, 0.4, 14.6)
	techo.mesh = box_t
	techo.position.y = 3.2
	var mat_tg = StandardMaterial3D.new()
	mat_tg.albedo_color = Color(0.7, 0.72, 0.75)
	techo.material_override = mat_tg
	seguidor.add_child(techo)
	
	var pantografo = MeshInstance3D.new()
	var box_p = BoxMesh.new()
	box_p.size = Vector3(1.2, 1.6, 1.8)
	pantografo.mesh = box_p
	pantografo.position = Vector3(0, 4.4, 0)
	var mat_p = StandardMaterial3D.new()
	mat_p.albedo_color = Color(0.2, 0.2, 0.2)
	pantografo.material_override = mat_p
	seguidor.add_child(pantografo)
	
	var cartel_led = Label3D.new()
	cartel_led.name = "CartelLED"
	cartel_led.text = "[ %s ] %s" % [num_linea, texto_led]
	cartel_led.font_size = 46
	cartel_led.outline_size = 14
	cartel_led.outline_modulate = Color.BLACK
	cartel_led.modulate = Color(1.0, 0.9, 0.1)
	cartel_led.position = Vector3(0, 2.9, 7.45)
	cartel_led.no_depth_test = true
	seguidor.add_child(cartel_led)
	
	_crear_luz_vehiculo(seguidor, Vector3(0, 2.5, 7.45), Color(1.0, 1.0, 0.9), 4.0, Vector3(0.5, 0.5, 0.2))
	_crear_luz_vehiculo(seguidor, Vector3(-0.7, 1.0, 7.45), Color(1.0, 1.0, 0.9), 3.5, Vector3(0.35, 0.35, 0.2))
	_crear_luz_vehiculo(seguidor, Vector3(0.7, 1.0, 7.45), Color(1.0, 1.0, 0.9), 3.5, Vector3(0.35, 0.35, 0.2))
	_crear_luz_vehiculo(seguidor, Vector3(-0.7, 1.0, -7.45), Color(0.95, 0.05, 0.05), 3.0, Vector3(0.35, 0.35, 0.2))
	_crear_luz_vehiculo(seguidor, Vector3(0.7, 1.0, -7.45), Color(0.95, 0.05, 0.05), 3.0, Vector3(0.35, 0.35, 0.2))

func _crear_luz_vehiculo(padre: Node3D, pos: Vector3, color: Color, energia: float, tam: Vector3) -> void:
	var luz = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = tam
	luz.mesh = box
	luz.position = pos
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energia
	luz.material_override = mat
	padre.add_child(luz)

func _intentar_agregar_parada_a_linea_existente(pos: Vector3) -> bool:
	var l: Path3D = _obtener_linea_cercana(pos)
	if l != null:
		var pto = l.curve.get_closest_point(pos)
		var off = l.curve.get_closest_offset(pto)
		_crear_poste_parada_caba(l, pto)
		var lista: Array = []
		if l.has_meta("paradas_metros"):
			lista = l.get_meta("paradas_metros")
		if not lista.has(off):
			lista.append(off)
			lista.sort()
			l.set_meta("paradas_metros", lista)
		for c in l.get_children():
			if c is PathFollow3D and c.has_method("agregar_nueva_parada"):
				c.agregar_nueva_parada(off)
		return true
	return false

func _crear_poste_parada_caba(linea: Path3D, pos: Vector3) -> void:
	var parada_root = Node3D.new()
	parada_root.position = pos + Vector3(3.2, 0, 0)
	
	var cano = MeshInstance3D.new()
	var cil = CylinderMesh.new()
	cil.top_radius = 0.18; cil.bottom_radius = 0.22; cil.height = 5.4
	cano.mesh = cil
	cano.position.y = 2.7
	var mat_negro = StandardMaterial3D.new()
	mat_negro.albedo_color = Color("#141414")
	cano.material_override = mat_negro
	parada_root.add_child(cano)
	
	var cartel_chapa = MeshInstance3D.new()
	var box_c = BoxMesh.new()
	box_c.size = Vector3(2.2, 1.15, 0.14)
	cartel_chapa.mesh = box_c
	cartel_chapa.position = Vector3(-1.15, 4.6, 0)
	var mat_chapa = StandardMaterial3D.new()
	mat_chapa.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_chapa.albedo_color = Color("#1c1e22")
	cartel_chapa.material_override = mat_chapa
	parada_root.add_child(cartel_chapa)
	
	var cuadro_color = MeshInstance3D.new()
	var box_col = BoxMesh.new()
	box_col.size = Vector3(0.95, 1.15, 0.18)
	cuadro_color.mesh = box_col
	cuadro_color.position = Vector3(0.55, 4.6, 0)
	var mat_col = StandardMaterial3D.new()
	mat_col.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_col.albedo_color = linea.get_meta("color_linea", Color("#0072bc"))
	cuadro_color.material_override = mat_col
	parada_root.add_child(cuadro_color)
	
	var num_str = str(linea.get_meta("numero_linea", "100"))
	var letra_str = str(linea.get_meta("letra_ramal", "A"))
	var lbl_num = Label3D.new()
	lbl_num.text = "%s\n(%s)" % [num_str, letra_str]
	lbl_num.font_size = 40
	lbl_num.outline_size = 12
	lbl_num.position = Vector3(0.55, 4.6, 0.12)
	lbl_num.no_depth_test = true
	parada_root.add_child(lbl_num)
	
	var grupo_p = Node3D.new()
	grupo_p.name = "GrupoPersonas"
	parada_root.add_child(grupo_p)
	
	parada_root.set_meta("numero_linea", num_str)
	parada_root.set_meta("letra_ramal", letra_str)
	parada_root.set_meta("pasajeros_esperando", 0)
	
	linea.add_child(parada_root)
	paradas_nodos.append(parada_root)

func _intentar_borrar_linea(pos: Vector3) -> bool:
	var l: Path3D = _obtener_linea_cercana(pos)
	if l != null:
		l.queue_free()
		return true
	return false

func _obtener_linea_cercana(pos: Vector3) -> Path3D:
	var mejor_dist: float = 90.0
	var linea_obj: Path3D = null
	for hijo in get_children():
		if hijo is Path3D and hijo != via_actual and hijo.curve:
			var pto = hijo.curve.get_closest_point(pos)
			var dist = pos.distance_to(pto)
			if dist < mejor_dist:
				mejor_dist = dist
				linea_obj = hijo
	return linea_obj

func _obtener_click_en_suelo(mouse_pos: Vector2):
	var rayo_o = camara.project_ray_origin(mouse_pos)
	var rayo_d = camara.project_ray_normal(mouse_pos)
	if abs(rayo_d.y) > 0.0001:
		var t = (altura_via - rayo_o.y) / rayo_d.y
		if t > 0:
			return rayo_o + rayo_d * t
	return null

func _aplicar_snapping_calle(pos_3d: Vector3):
	if imagen_mapa == null:
		return pos_3d
	var mesh_plane: PlaneMesh = mapa_fondo.mesh as PlaneMesh
	if mesh_plane == null:
		return pos_3d
	var ancho_m = mesh_plane.size.x
	var alto_m = mesh_plane.size.y
	var u = (pos_3d.x / ancho_m) + 0.5
	var v = (pos_3d.z / alto_m) + 0.5
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return null
	var img_w = imagen_mapa.get_width()
	var img_h = imagen_mapa.get_height()
	var px = int(u * img_w)
	var py = int(v * img_h)
	var mejor_dist_sq = 99999.0
	var mejor_px = px
	var mejor_py = py
	var encontro = false
	for dy in range(-radio_busqueda_snap, radio_busqueda_snap + 1):
		for dx in range(-radio_busqueda_snap, radio_busqueda_snap + 1):
			var cx = clamp(px + dx, 0, img_w - 1)
			var cy = clamp(py + dy, 0, img_h - 1)
			var col = imagen_mapa.get_pixel(cx, cy)
			if _colores_similares(col, color_asfalto, tolerancia_color):
				var dsq = float(dx * dx + dy * dy)
				if dsq < mejor_dist_sq:
					mejor_dist_sq = dsq
					mejor_px = cx
					mejor_py = cy
					encontro = true
	if encontro:
		var nu = (float(mejor_px) + 0.5) / float(img_w)
		var nv = (float(mejor_py) + 0.5) / float(img_h)
		return Vector3((nu - 0.5) * ancho_m, pos_3d.y, (nv - 0.5) * alto_m)
	return null

func _colores_similares(c1: Color, c2: Color, tol: float) -> bool:
	var dr = c1.r - c2.r
	var dg = c1.g - c2.g
	var db = c1.b - c2.b
	return sqrt(dr * dr + dg * dg + db * db) < tol

func _detectar_colectivo_bajo_mouse(mouse_pos: Vector2) -> Node3D:
	var rayo_o = camara.project_ray_origin(mouse_pos)
	var rayo_d = camara.project_ray_normal(mouse_pos)
	var colectivos = get_tree().get_nodes_in_group("colectivos")
	for col in colectivos:
		if is_instance_valid(col) and col.visible:
			var pos_b = col.global_position
			var vec = pos_b - rayo_o
			var proj = vec.dot(rayo_d)
			if proj > 0.0:
				var pto = rayo_o + rayo_d * proj
				if pto.distance_to(pos_b) <= 12.0:
					return col
	return null

func _deshacer_ultimo_punto() -> void:
	if via_actual == null:
		return
	if estado_desdoble == 1 and buffer_rama_ida.size() > 1:
		buffer_rama_ida.pop_back()
	elif estado_desdoble == 2 and buffer_rama_vuelta.size() > 1:
		buffer_rama_vuelta.pop_back()
	elif not tramos_konstruccion.is_empty():
		var ult_tr = tramos_konstruccion.back()
		if ult_tr["tipo"] == "doble" and ult_tr["puntos"].size() > 1:
			ult_tr["puntos"].pop_back()
	_reconstruir_curva_y_malla_actual()

func _cancelar_linea_en_curso() -> void:
	if via_actual != null:
		_limpiar_marcadores_desdoble()
		via_actual.queue_free()
		via_actual = null
		malla_linea = null
		estado_desdoble = 0
		if btn_desdoblar:
			btn_desdoblar.text = "🔀 Desdoblar 1 Mano (V)"

func _alternar_lista_lineas() -> void:
	if ventana_lista_lineas != null and is_instance_valid(ventana_lista_lineas):
		ventana_lista_lineas.queue_free()
		ventana_lista_lineas = null
		return

	ventana_lista_lineas = Window.new()
	ventana_lista_lineas.title = "Red de Transporte - Lista de Líneas y Ramales"
	ventana_lista_lineas.size = Vector2i(620, 500)
	ventana_lista_lineas.position = Vector2i(660, 320)
	ventana_lista_lineas.close_requested.connect(func(): ventana_lista_lineas.queue_free())
	
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 16; scroll.offset_top = 16
	scroll.offset_right = -16; scroll.offset_bottom = -16
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var cant_lineas = 0
	for hijo in get_children():
		if hijo is Path3D and hijo.curve and hijo.curve.point_count > 0:
			cant_lineas += 1
			var num = hijo.get_meta("numero_linea", "?")
			var ramal = hijo.get_meta("nombre_ramal", "Troncal")
			var ramal_letra = hijo.get_meta("letra_ramal", "A")
			var tipo = hijo.get_meta("tipo_transporte", "colectivo")
			var col: Color = hijo.get_meta("color_linea", Color.WHITE)
			var flota = hijo.get_children().filter(func(n): return n is PathFollow3D).size()
			var tag_conurbano = " [➡️ Conurbano]" if hijo.get_meta("sale_al_conurbano", false) else ""
			
			var hbox = HBoxContainer.new()
			var lbl_info = RichTextLabel.new()
			lbl_info.fit_content = true
			lbl_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl_info.bbcode_enabled = true
			lbl_info.text = "[color=#%s]■ %s %s (R%s)[/color] - %s%s [color=#888888](Flota: %d)[/color]" % [col.to_html(false), tipo.to_upper(), num, ramal_letra, ramal, tag_conurbano, flota]
			hbox.add_child(lbl_info)
			
			var btn_resaltar = Button.new()
			btn_resaltar.text = "✨ Resaltar"
			btn_resaltar.pressed.connect(func():
				_resaltar_linea_completa(hijo)
			)
			hbox.add_child(btn_resaltar)
			
			var btn_editar = Button.new()
			btn_editar.text = "✏️ Editar"
			btn_editar.pressed.connect(func():
				_resaltar_linea_completa(hijo)
				_abrir_editor_ramal(hijo)
			)
			hbox.add_child(btn_editar)
			
			var btn_ir = Button.new()
			btn_ir.text = "👁️ Ver"
			btn_ir.pressed.connect(func():
				var primer_coche = hijo.get_children().filter(func(n): return n is PathFollow3D)
				if not primer_coche.is_empty():
					objetivo_seguimiento = primer_coche[0]
					panel_telemetria.visible = true
				else:
					camara.global_position = hijo.curve.get_point_position(0) + Vector3(0, 150, 90)
				ventana_lista_lineas.queue_free()
			)
			hbox.add_child(btn_ir)
			
			vbox.add_child(hbox)
			vbox.add_child(HSeparator.new())

	if cant_lineas == 0:
		var lbl_vacio = Label.new()
		lbl_vacio.text = "No hay líneas inauguradas en el mapa."
		vbox.add_child(lbl_vacio)

	scroll.add_child(vbox)
	ventana_lista_lineas.add_child(scroll)
	canvas_hud.add_child(ventana_lista_lineas)

func _alternar_menu_ayuda() -> void:
	if ventana_ayuda != null and is_instance_valid(ventana_ayuda):
		ventana_ayuda.queue_free()
		ventana_ayuda = null
		return

	ventana_ayuda = Window.new()
	ventana_ayuda.title = "Comandos y Atajos del Juego"
	ventana_ayuda.size = Vector2i(650, 620)
	ventana_ayuda.position = Vector2i(680, 290)
	ventana_ayuda.close_requested.connect(func(): ventana_ayuda.queue_free())
	
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var lbl = RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.text = """
[font_size=20][b]GUÍA MAESTRA DE COMANDOS[/b][/font_size]

[b]D[/b] - Modo Depósito Colectivos / [b]Shift + D[/b] - Depósito Premetro
[b]T[/b] - [color=#66ffcc]Estación Metrobús (Conecta hasta 6 líneas con personitas)[/color]
[b]G[/b] - [color=#ff9933]Pórtico Salida al Conurbano (Editable con tecla I)[/color]
[b]Botón Modo Recorrido[/b] - Elegir entre [b]Ida y Vuelta[/b] o [b]Terminal a Terminal[/b]
[b]V[/b] - [color=#ffcc66]Desdoblar 1 Mano (Conecta los 2 carriles a 2 calles de 1 mano)[/color]
[b]R[/b] - [color=#66ff66]Rotar edificio en previsualización / Abrir Zonas RCI por m³[/color]
[b]Shift / P + Clic[/b] - Clavar Parada CABA con cuadradito de color y pasajeros
[b]S[/b] - Modo Semáforo CABA (Instala 4 postes amarillos de 3 ópticas en el cruce)
[b]Clic en Parada / Metrobús / Semáforo[/b] - Ver pasajeros esperando o editar fases
[b]L[/b] - [color=#66ffaa]Lista General de Líneas (Editar, Resaltar y Seguir)[/color]
[b]I + Clic en Edificio o Pórtico[/b] - [color=#66ccff]Rotar 360° o editar texto del cartel[/color]
[b]Espacio / Enter[/b] - Inaugurar línea / Cerrar Polígono RCI
[b]Z[/b] - Deshacer último punto / [b]C[/b] - Cancelar trazado
[b]K + Clic[/b] - Borrar Semáforo / [b]J + Clic[/b] - Borrar Edificios o Paradas
[b]X + Clic[/b] - Eliminar Línea completa / [b]E[/b] - Editar Línea bajo el cursor
"""
	panel.add_child(lbl)
	ventana_ayuda.add_child(panel)
	canvas_hud.add_child(ventana_ayuda)

func _crear_interfaz_hud() -> void:
	canvas_hud = CanvasLayer.new()
	add_child(canvas_hud)
	
	var toolbar = PanelContainer.new()
	toolbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var sb_t = StyleBoxFlat.new()
	sb_t.bg_color = Color(0.1, 0.12, 0.15, 0.95)
	sb_t.content_margin_top = 8; sb_t.content_margin_bottom = 8
	sb_t.content_margin_left = 12; sb_t.content_margin_right = 12
	toolbar.add_theme_stylebox_override("panel", sb_t)
	
	var hbox_t = HBoxContainer.new()
	hbox_t.add_theme_constant_override("separation", 8)
	
	var btn_dep_b = Button.new()
	btn_dep_b.text = "🏢 Depósito (D)"
	btn_dep_b.focus_mode = Control.FOCUS_NONE
	btn_dep_b.pressed.connect(func(): _activar_modo_colocacion_edificio("deposito_bondi"))
	hbox_t.add_child(btn_dep_b)
	
	var btn_trans = Button.new()
	btn_trans.text = "🚏 Metrobús 6L (T)"
	btn_trans.focus_mode = Control.FOCUS_NONE
	btn_trans.pressed.connect(func(): _activar_modo_colocacion_edificio("transbordo"))
	hbox_t.add_child(btn_trans)
	
	var btn_conurbano = Button.new()
	btn_conurbano.text = "➡️ Conurbano (G)"
	btn_conurbano.focus_mode = Control.FOCUS_NONE
	btn_conurbano.pressed.connect(func(): _activar_modo_colocacion_edificio("conurbano"))
	hbox_t.add_child(btn_conurbano)
	
	hbox_t.add_child(VSeparator.new())
	
	btn_modo_recorrido = Button.new()
	btn_modo_recorrido.text = "🔄 Modo: Ida y Vuelta"
	btn_modo_recorrido.focus_mode = Control.FOCUS_NONE
	btn_modo_recorrido.pressed.connect(func():
		exigir_regreso_a_deposito = !exigir_regreso_a_deposito
		btn_modo_recorrido.text = "🏁 Modo: Terminal a Terminal" if exigir_regreso_a_deposito else "🔄 Modo: Ida y Vuelta"
	)
	hbox_t.add_child(btn_modo_recorrido)
	
	btn_desdoblar = Button.new()
	btn_desdoblar.text = "🔀 Desdoblar 1 Mano (V)"
	btn_desdoblar.focus_mode = Control.FOCUS_NONE
	btn_desdoblar.pressed.connect(_alternar_desdoble_una_mano)
	hbox_t.add_child(btn_desdoblar)
	
	hbox_t.add_child(VSeparator.new())
	
	var btn_sem = Button.new()
	btn_sem.text = "🚦 Semáforo (S)"
	btn_sem.focus_mode = Control.FOCUS_NONE
	btn_sem.pressed.connect(func(): modo_semaforo = !modo_semaforo)
	hbox_t.add_child(btn_sem)
	
	var btn_lista = Button.new()
	btn_lista.text = "📋 Líneas (L)"
	btn_lista.focus_mode = Control.FOCUS_NONE
	btn_lista.pressed.connect(_alternar_lista_lineas)
	hbox_t.add_child(btn_lista)
	
	var btn_rci = Button.new()
	btn_rci.text = "🏙️ Zonas RCI (R)"
	btn_rci.focus_mode = Control.FOCUS_NONE
	btn_rci.pressed.connect(_abrir_panel_seleccion_rci)
	hbox_t.add_child(btn_rci)
	
	var btn_ayuda = Button.new()
	btn_ayuda.text = "❓ (H)"
	btn_ayuda.focus_mode = Control.FOCUS_NONE
	btn_ayuda.pressed.connect(_alternar_menu_ayuda)
	hbox_t.add_child(btn_ayuda)
	
	lbl_reloj_hud = Label.new()
	lbl_reloj_hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_reloj_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_reloj_hud.add_theme_font_size_override("font_size", 18)
	hbox_t.add_child(lbl_reloj_hud)
	
	toolbar.add_child(hbox_t)
	canvas_hud.add_child(toolbar)
	
	panel_telemetria = PanelContainer.new()
	panel_telemetria.position = Vector2(25, 820)
	panel_telemetria.custom_minimum_size = Vector2(500, 310)
	panel_telemetria.visible = false
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.13, 0.94)
	sb.corner_radius_top_left = 12; sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12; sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 18; sb.content_margin_top = 18
	sb.content_margin_right = 18; sb.content_margin_bottom = 18
	panel_telemetria.add_theme_stylebox_override("panel", sb)
	
	var vbox_tel = VBoxContainer.new()
	label_telemetria = RichTextLabel.new()
	label_telemetria.bbcode_enabled = true
	label_telemetria.fit_content = true
	vbox_tel.add_child(label_telemetria)
	vbox_tel.add_child(HSeparator.new())
	
	var hbox_cartel = HBoxContainer.new()
	var lbl_tag = Label.new()
	lbl_tag.text = "Cartelera LED:"
	hbox_cartel.add_child(lbl_tag)
	
	txt_numero_input = LineEdit.new()
	txt_numero_input.custom_minimum_size.x = 75
	txt_numero_input.placeholder_text = "Núm"
	txt_numero_input.text_changed.connect(_al_cambiar_numero_vehiculo)
	hbox_cartel.add_child(txt_numero_input)
	
	txt_cartelera_input = LineEdit.new()
	txt_cartelera_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt_cartelera_input.placeholder_text = "Destino cartelera..."
	txt_cartelera_input.text_changed.connect(_al_cambiar_texto_cartelera_vehiculo)
	hbox_cartel.add_child(txt_cartelera_input)
	
	vbox_tel.add_child(hbox_cartel)
	panel_telemetria.add_child(vbox_tel)
	canvas_hud.add_child(panel_telemetria)

func _actualizar_telemetria_hud() -> void:
	if objetivo_seguimiento == null or not is_instance_valid(objetivo_seguimiento):
		return
	var linea: Path3D = objetivo_seguimiento.get_parent() as Path3D
	var num = linea.get_meta("numero_linea", "100") if linea else "S/D"
	var ramal = linea.get_meta("nombre_ramal", "Troncal") if linea else "S/D"
	var ramal_letra = linea.get_meta("letra_ramal", "A") if linea else "A"
	var col_hex = (linea.get_meta("color_linea", Color.WHITE) as Color).to_html(false) if linea else "FFFFFF"
	var tipo = linea.get_meta("tipo_transporte", "colectivo") if linea else "colectivo"
	
	var vel_kmh = snapped(objetivo_seguimiento.get("velocidad_actual") * 3.6, 0.1)
	var vel_prom = snapped(objetivo_seguimiento.get("velocidad_promedio_kmh"), 0.1)
	var dist_sig = objetivo_seguimiento.call("obtener_distancia_siguiente_parada")
	var t_parada = (str(snapped(dist_sig, 1)) + " m") if dist_sig >= 0.0 else "Sin paradas pendientes"
	var t_viaje = int(objetivo_seguimiento.get("tiempo_viaje_transcurrido"))
	var t_restante = int(objetivo_seguimiento.call("obtener_tiempo_restante_estimado"))
	var pct = snapped(objetivo_seguimiento.call("obtener_porcentaje_completado"), 0.1)
	var pasajeros = int(objetivo_seguimiento.get("pasajeros_a_bordo"))
	var en_prov = bool(objetivo_seguimiento.get("en_conurbano"))
	var t_prov_rest = int(objetivo_seguimiento.get("temporizador_conurbano_min"))
	
	var bbcode = "[font_size=24][color=#%s]■ %s %s[/color][/font_size] [color=#aaaaaa]| Ramal %s: %s[/color]\n" % [col_hex, tipo.to_upper(), num, ramal_letra, ramal]
	bbcode += "[font_size=17][b]%s[/b][/font_size]\n" % objetivo_seguimiento.name
	if en_prov:
		bbcode += "[color=#ff9933][b]➡️ EN EL CONURBANO (Regresa a CABA en %d min)[/b][/color]\n" % t_prov_rest
	else:
		bbcode += "[b]Velocidad:[/b] %s km/h  [color=#888888](Prom: %s km/h)[/color]\n" % [vel_kmh, vel_prom]
	bbcode += "[b]Ocupación:[/b] %d / 45 pasajeros  |  [b]Próxima Parada:[/b] %s\n" % [pasajeros, t_parada]
	bbcode += "[b]Progreso:[/b] %s%%  |  [b]Viaje:[/b] %02d:%02d  |  [b]Restante:[/b] %02d:%02d" % [pct, t_viaje / 60, t_viaje % 60, t_restante / 60, t_restante % 60]
	label_telemetria.text = bbcode
	
	if not txt_numero_input.has_focus():
		txt_numero_input.text = str(num)
	if not txt_cartelera_input.has_focus() and linea != null:
		txt_cartelera_input.text = linea.get_meta("cartelera_led", "A CABECERA")

func _al_cambiar_numero_vehiculo(nuevo_numero: String) -> void:
	if objetivo_seguimiento == null or not is_instance_valid(objetivo_seguimiento):
		return
	var linea = objetivo_seguimiento.get_parent()
	if linea:
		linea.set_meta("numero_linea", nuevo_numero)
		_actualizar_led_en_flota(linea)

func _al_cambiar_texto_cartelera_vehiculo(nuevo_texto: String) -> void:
	if objetivo_seguimiento == null or not is_instance_valid(objetivo_seguimiento):
		return
	var linea = objetivo_seguimiento.get_parent()
	if linea:
		linea.set_meta("cartelera_led", nuevo_texto.to_upper())
		_actualizar_led_en_flota(linea)

func _actualizar_led_en_flota(linea: Path3D) -> void:
	var num = linea.get_meta("numero_linea", "100")
	var txt = linea.get_meta("cartelera_led", "A CABECERA")
	var ramal_letra = linea.get_meta("letra_ramal", "A")
	var tipo_cartel = linea.get_meta("tipo_cartelera", "digital")
	
	for c in linea.get_children():
		if c is PathFollow3D:
			var visor = c.get_node_or_null("VisorCaja") as MeshInstance3D
			if visor and visor.material_override:
				(visor.material_override as StandardMaterial3D).albedo_color = Color("#080808") if tipo_cartel == "digital" else Color("#f2f2f2")
			var led = c.get_node_or_null("CartelLED") as Label3D
			if led:
				led.modulate = Color("#ffb300") if tipo_cartel == "digital" else Color("#111111")
				led.text = ("[%s] %s (R%s)   *   " % [num, txt, ramal_letra]) if tipo_cartel == "digital" else ("%s (R%s)" % [txt, ramal_letra])
			var num_lbl = c.get_node_or_null("CartelNumero") as Label3D
			if num_lbl:
				num_lbl.modulate = Color("#ffb300") if tipo_cartel == "digital" else Color("#111111")
				num_lbl.text = num

func _abrir_editor_ramal(linea: Path3D) -> void:
	if ventana_edicion_linea != null and is_instance_valid(ventana_edicion_linea):
		ventana_edicion_linea.queue_free()
	ventana_edicion_linea = Window.new()
	ventana_edicion_linea.title = "Configurar Línea, Ramal y Conurbano"
	ventana_edicion_linea.size = Vector2i(480, 520)
	ventana_edicion_linea.position = Vector2i(600, 300)
	ventana_edicion_linea.close_requested.connect(func(): ventana_edicion_linea.queue_free())
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20; vbox.offset_top = 20
	vbox.offset_right = -20; vbox.offset_bottom = -20
	
	var lbl_num = Label.new()
	lbl_num.text = "Número de Línea:"
	vbox.add_child(lbl_num)
	var txt_num = LineEdit.new()
	txt_num.text = str(linea.get_meta("numero_linea", "166"))
	vbox.add_child(txt_num)
	
	var lbl_letra = Label.new()
	lbl_letra.text = "Letra de Ramal:"
	vbox.add_child(lbl_letra)
	var opt_letra = OptionButton.new()
	for ltr in ["A", "B", "C", "D", "E", "R1", "R2", "EXPRESO"]:
		opt_letra.add_item(ltr)
	opt_letra.text = linea.get_meta("letra_ramal", "A")
	vbox.add_child(opt_letra)
	
	var lbl_ramal = Label.new()
	lbl_ramal.text = "Nombre / Destino del Ramal:"
	vbox.add_child(lbl_ramal)
	var txt_ramal = LineEdit.new()
	txt_ramal.text = str(linea.get_meta("nombre_ramal", "Troncal"))
	vbox.add_child(txt_ramal)
	
	var lbl_tipo_c = Label.new()
	lbl_tipo_c.text = "Estilo de Cartelera:"
	vbox.add_child(lbl_tipo_c)
	
	var opt_tipo_cartel = OptionButton.new()
	opt_tipo_cartel.add_item("Digital LED (Marquesina Ámbar)", 0)
	opt_tipo_cartel.add_item("Clásica de Acrílico (Letras Negras)", 1)
	opt_tipo_cartel.selected = 0 if linea.get_meta("tipo_cartelera", "digital") == "digital" else 1
	vbox.add_child(opt_tipo_cartel)
	
	var slider_conurbano: HSlider = null
	if linea.get_meta("sale_al_conurbano", false):
		vbox.add_child(HSeparator.new())
		var t_actual = float(linea.get_meta("tiempo_conurbano_min", 90.0))
		var lbl_con = Label.new()
		lbl_con.text = "➡️ Tiempo Base en Conurbano: %d min (±10-15m x coche)" % int(t_actual)
		vbox.add_child(lbl_con)
		
		slider_conurbano = HSlider.new()
		slider_conurbano.min_value = 30.0
		slider_conurbano.max_value = 150.0
		slider_conurbano.step = 5.0
		slider_conurbano.value = t_actual
		slider_conurbano.value_changed.connect(func(v: float):
			lbl_con.text = "➡️ Tiempo Base en Conurbano: %d min (±10-15m x coche)" % int(v)
		)
		vbox.add_child(slider_conurbano)
	
	vbox.add_child(HSeparator.new())
	
	var btn_crear_ramal = Button.new()
	btn_crear_ramal.text = "➕ Crear Nuevo Ramal desde Cabecera"
	btn_crear_ramal.pressed.connect(func():
		linea_padre_para_ramal = linea
		var pos_inicio = linea.curve.get_point_position(0)
		camara.global_position = pos_inicio + Vector3(0, 160, 90)
		ventana_edicion_linea.queue_free()
	)
	vbox.add_child(btn_crear_ramal)
	
	var btn = Button.new()
	btn.text = "Guardar Cambios"
	btn.pressed.connect(func():
		linea.set_meta("numero_linea", txt_num.text)
		linea.set_meta("letra_ramal", opt_letra.get_item_text(opt_letra.selected))
		linea.set_meta("nombre_ramal", txt_ramal.text)
		linea.set_meta("tipo_cartelera", "digital" if opt_tipo_cartel.selected == 0 else "clasica")
		if slider_conurbano != null:
			linea.set_meta("tiempo_conurbano_min", slider_conurbano.value)
		_actualizar_led_en_flota(linea)
		ventana_edicion_linea.queue_free()
	)
	vbox.add_child(btn)
	ventana_edicion_linea.add_child(vbox)
	canvas_hud.add_child(ventana_edicion_linea)
