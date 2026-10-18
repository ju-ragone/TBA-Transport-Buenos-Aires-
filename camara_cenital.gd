extends Camera3D

@export var velocidad_arrastre: float = 0.8   # Más ágil para resolución 2K
@export var velocidad_zoom: float = 15.0      # Zoom más rápido
@export var altura_minima: float = 20.0       
@export var altura_maxima: float = 2500.0     

var arrastrando: bool = false
var ultima_posicion_mouse: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Altura inicial equilibrada para 1440p
	position = Vector3(0, 250, 150)
	rotation_degrees = Vector3(-60, 0, 0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			arrastrando = event.pressed
			ultima_posicion_mouse = event.position
		
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_ajustar_zoom(-velocidad_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_ajustar_zoom(velocidad_zoom)

	elif event is InputEventMouseMotion and arrastrando:
		var delta_mouse: Vector2 = event.position - ultima_posicion_mouse
		ultima_posicion_mouse = event.position
		
		# Ajuste de escala de paneo considerando la resolución más alta
		var factor_escala: float = position.y * 0.0015 * velocidad_arrastre
		position.x -= delta_mouse.x * factor_escala * 30.0
		position.z -= delta_mouse.y * factor_escala * 30.0

func _ajustar_zoom(cantidad: float) -> void:
	position.y = clamp(position.y + cantidad, altura_minima, altura_maxima)
	position.z = clamp(position.z + (cantidad * 0.6), altura_minima * 0.6, altura_maxima * 0.6)
