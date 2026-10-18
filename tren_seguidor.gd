extends PathFollow3D

@export var velocidad_crucero: float = 12.5
@export var aceleracion: float = 3.8
@export var frenado: float = 9.0
@export var tiempo_espera_parada: float = 2.5
@export var tiempo_espera_cabecera: float = 4.0

var velocidad_actual: float = 0.0
var parada_activa: bool = false
var temporizador_parada: float = 0.0
var direccion: float = 1.0
var longitud_total_linea: float = 0.0

var paradas_metros: Array = []
var paradas_visitadas: Dictionary = {}

var tiempo_viaje_transcurrido: float = 0.0
var distancia_total_recorrida: float = 0.0
var velocidad_promedio_kmh: float = 0.0

var timer_scroll_led: float = 0.0
var pasajeros_a_bordo: int = 0

# Variables de Excursión al Conurbano
var en_conurbano: bool = false
var temporizador_conurbano_min: float = 0.0
var conurbano_visitado_en_vuelta: bool = false

# Segmentación por Cantones Ferroviarios (Anti-trencito)
const LARGO_CANTON: float = 65.0
var canton_actual: int = 0
var progress_anterior: float = 0.0
var mitad_recorrido_visitada: bool = false

func _ready() -> void:
	progress = 0.0
	progress_anterior = 0.0
	h_offset = 0.0
	_actualizar_longitud()

func _actualizar_longitud() -> void:
	var linea = get_parent()
	if linea is Path3D and linea.curve:
		longitud_total_linea = linea.curve.get_baked_length()

func _physics_process(delta: float) -> void:
	if longitud_total_linea <= 1.0:
		_actualizar_longitud()
		if longitud_total_linea <= 1.0:
			return

	tiempo_viaje_transcurrido += delta
	distancia_total_recorrida += abs(velocidad_actual * delta)
	if tiempo_viaje_transcurrido > 0.5:
		velocidad_promedio_kmh = (distancia_total_recorrida / tiempo_viaje_transcurrido) * 3.6

	# 1. Simulación de viaje por el Conurbano (30m a 150m ± 10-15m individuales)
	if en_conurbano:
		temporizador_conurbano_min -= delta * 3.0
		if temporizador_conurbano_min <= 0.0:
			en_conurbano = false
			visible = true
			pasajeros_a_bordo = randi_range(32, 45)
		return

	if parada_activa:
		temporizador_parada -= delta
		if temporizador_parada <= 0.0:
			parada_activa = false
		return

	# 2. Control de Vuelta Completa y Cabecera Opuesta (sin retroceder marcha atrás)
	var punto_mitad: float = longitud_total_linea * 0.5
	if not mitad_recorrido_visitada and progress >= punto_mitad and abs(progress - punto_mitad) < 2.0:
		mitad_recorrido_visitada = true
		paradas_visitadas.clear() # Limpia las paradas para que también levante gente a la vuelta
		
	if progress < progress_anterior:
		# Cerró la vuelta entera en el depósito cabecera
		_llegada_a_cabecera(1.0)
		progress_anterior = progress
		return

	_chequear_salida_conurbano()

	# 3. SEGMENTACIÓN POR CANTONES Y ANTICOLISIÓN ELÁSTICA
	canton_actual = int(progress / LARGO_CANTON)
	var datos_lider = _obtener_vehiculo_adelante()
	var distancia_frente: float = datos_lider["distancia"]
	var vel_lider: float = datos_lider["velocidad"]
	var canton_lider: int = datos_lider["canton"]
	
	var velocidad_deseada: float = velocidad_crucero
	
	if distancia_frente < 26.0:
		velocidad_deseada = 0.0
	elif canton_lider == canton_actual or distancia_frente < 65.0:
		velocidad_deseada = min(velocidad_crucero * 0.42, max(vel_lider * 0.65, 2.5))
	elif distancia_frente < 110.0:
		velocidad_deseada = min(velocidad_crucero * 0.78, vel_lider * 0.9)

	# 4. SEMÁFOROS EN ROJO / AMARILLO: Frenado antes de la senda peatonal
	var distancia_sem = _obtener_distancia_a_semaforo_rojo()
	if distancia_sem >= 0.0:
		if distancia_sem <= 11.5:
			velocidad_deseada = 0.0
		elif distancia_sem < 28.0:
			velocidad_deseada = min(velocidad_deseada, lerp(1.8, velocidad_crucero, (distancia_sem - 11.5) / 16.5))

	# 5. Paradas oficiales CABA y Estaciones de Metrobús (detecta paradas en ambos carriles)
	var linea_p = get_parent()
	var mundo = linea_p.get_parent() if linea_p else null
	if mundo:
		for p_nodo in mundo.paradas_nodos:
			if is_instance_valid(p_nodo) and p_nodo.get_parent() == linea_p:
				var id_p = p_nodo.get_instance_id()
				if not paradas_visitadas.has(id_p) and global_position.distance_to(p_nodo.global_position) <= 6.5:
					_frenar_en_parada(id_p)
					return
		for mb_nodo in mundo.centros_transbordo_nodos:
			if is_instance_valid(mb_nodo):
				var id_mb = mb_nodo.get_instance_id()
				if not paradas_visitadas.has(id_mb) and global_position.distance_to(mb_nodo.global_position) <= 5.5:
					_frenar_en_parada(id_mb)
					return

	# Aplicar cinemática siempre hacia adelante sobre el carril físico correspondiente
	progress_anterior = progress
	velocidad_actual = move_toward(velocidad_actual, velocidad_deseada, frenado * delta if velocidad_deseada < velocidad_actual else aceleracion * delta)
	progress += velocidad_actual * delta

	_animar_cartel_led(delta)

func _chequear_salida_conurbano() -> void:
	if en_conurbano or conurbano_visitado_en_vuelta:
		return
	var linea = get_parent()
	if linea == null or not linea.get_meta("sale_al_conurbano", false):
		return
		
	var metro_con = float(linea.get_meta("metro_conurbano", -1.0))
	if metro_con >= 0.0 and abs(progress - metro_con) < 4.5:
		en_conurbano = true
		conurbano_visitado_en_vuelta = true
		visible = false
		velocidad_actual = 0.0
		
		var base_min = float(linea.get_meta("tiempo_conurbano_min", 90.0))
		var desviacion_coche = randf_range(10.0, 15.0) * (-1.0 if randf() < 0.5 else 1.0)
		temporizador_conurbano_min = clamp(base_min + desviacion_coche, 20.0, 165.0)

func _obtener_vehiculo_adelante() -> Dictionary:
	if progress < 12.0 or progress > (longitud_total_linea - 12.0):
		return {"distancia": 9999.0, "velocidad": velocidad_crucero, "canton": -99}
		
	var linea = get_parent()
	if not linea is Path3D:
		return {"distancia": 9999.0, "velocidad": velocidad_crucero, "canton": -99}
		
	var menor_dist: float = 9999.0
	var v_lider: float = velocidad_crucero
	var c_lider: int = -99
	
	for hermano in linea.get_children():
		if hermano is PathFollow3D and hermano != self and hermano.visible:
			var delta_s = hermano.progress - self.progress
			if delta_s > 0.0 and delta_s < 120.0:
				if delta_s < menor_dist:
					menor_dist = delta_s
					v_lider = hermano.get("velocidad_actual")
					c_lider = int(hermano.progress / LARGO_CANTON)
						
	return {"distancia": menor_dist, "velocidad": v_lider, "canton": c_lider}

func _obtener_distancia_a_semaforo_rojo() -> float:
	var linea = get_parent()
	if linea == null or not linea.has_meta("semaforos"):
		return -1.0
	var dict_sem = linea.get_meta("semaforos", {})
	if not (dict_sem is Dictionary) or dict_sem.is_empty():
		return -1.0
		
	var menor_dist: float = 9999.0
	for metro_s in dict_sem.keys():
		if dict_sem[metro_s]:
			var dist = float(metro_s) - self.progress
			if dist >= 6.5 and dist < menor_dist:
				menor_dist = dist
	return menor_dist if menor_dist <= 28.0 else -1.0

func _frenar_en_parada(id_parada: int) -> void:
	velocidad_actual = 0.0
	parada_activa = true
	var dist_adelante = _obtener_vehiculo_adelante()["distancia"]
	var extra_regulacion = 3.5 if dist_adelante < 90.0 else 0.0
	temporizador_parada = tiempo_espera_parada + extra_regulacion
	paradas_visitadas[id_parada] = true
	
	var linea = get_parent()
	var mundo = linea.get_parent() if linea else null
	if mundo and mundo.has_method("procesar_intercambio_pasajeros_en_parada"):
		pasajeros_a_bordo = mundo.procesar_intercambio_pasajeros_en_parada(global_position, pasajeros_a_bordo, 45)

func _llegada_a_cabecera(_nueva_dir: float) -> void:
	velocidad_actual = 0.0
	parada_activa = true
	
	var dist_anterior = _obtener_vehiculo_adelante()["distancia"]
	var demora_despacho = 9.0 if dist_anterior < 140.0 else 0.0
	temporizador_parada = tiempo_espera_cabecera + demora_despacho
	
	paradas_visitadas.clear()
	mitad_recorrido_visitada = false
	conurbano_visitado_en_vuelta = false
	tiempo_viaje_transcurrido = 0.0
	distancia_total_recorrida = 0.0

func agregar_nueva_parada(metro_offset: float) -> void:
	if not paradas_metros.has(metro_offset):
		paradas_metros.append(metro_offset)
		paradas_metros.sort()

func _animar_cartel_led(delta: float) -> void:
	var cartel = get_node_or_null("CartelLED") as Label3D
	if cartel and cartel.modulate.r > 0.5:
		timer_scroll_led += delta
		if timer_scroll_led >= 0.25:
			timer_scroll_led = 0.0
			var txt = cartel.text
			if txt.length() > 10:
				cartel.text = txt.substr(1) + txt[0]

func resaltar_recorrido() -> void:
	var linea = get_parent()
	if linea is Path3D:
		var malla = linea.get_node_or_null("MallaCinta") as MeshInstance3D
		if malla and malla.material_override:
			var tween = create_tween()
			var mat = malla.material_override as StandardMaterial3D
			var col_linea: Color = linea.get_meta("color_linea", Color.WHITE)
			tween.tween_property(mat, "albedo_color", Color.WHITE, 0.25)
			tween.tween_property(mat, "albedo_color", col_linea, 0.4)

func obtener_distancia_siguiente_parada() -> float:
	var linea_p = get_parent()
	var mundo = linea_p.get_parent() if linea_p else null
	if mundo == null:
		return -1.0
	var menor_dist: float = 99999.0
	for p_nodo in mundo.paradas_nodos:
		if is_instance_valid(p_nodo) and p_nodo.get_parent() == linea_p:
			var id_p = p_nodo.get_instance_id()
			if not paradas_visitadas.has(id_p):
				var d = global_position.distance_to(p_nodo.global_position)
				if d < menor_dist:
					menor_dist = d
	return menor_dist if menor_dist < 99990.0 else -1.0

func obtener_porcentaje_completado() -> float:
	if longitud_total_linea <= 0.0:
		return 0.0
	return (progress / longitud_total_linea) * 100.0

func obtener_tiempo_restante_estimado() -> float:
	var v = max(velocidad_actual, 4.0)
	var dist_restante = max(0.0, longitud_total_linea - progress)
	return dist_restante / v
