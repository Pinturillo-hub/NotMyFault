shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 color_rastro : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec4 color_fondo : source_color = vec4(0.1, 0.1, 0.1, 1.0);
uniform float progreso : hint_range(0.0, 1.0) = 0.0;

// NUEVO: Offset para girar el inicio del relleno (en radianes)
// PI = 3.14159 (180 grados). Prueba valores como 3.14, 1.57, etc.
uniform float offset_rotacion = 3.14159; 

void fragment() {
	vec2 uv_centrado = UV - 0.5;
	float dist = length(uv_centrado);
	
	// Recorte circular
	if (dist > 0.5) {
		discard;
	}

	// Cálculo del ángulo
	// Sumamos el offset al ángulo calculado
	float angulo = atan(uv_centrado.x, -uv_centrado.y) + offset_rotacion;
	
	// Normalizamos (y aseguramos que siga entre 0 y 1 tras sumar el offset)
	// La función fract() nos da la parte decimal, haciendo un loop perfecto (0..1)
	float angulo_norm = fract((angulo / 6.28318) + 0.5);
	
	// Pintar
	if (angulo_norm < progreso) {
		ALBEDO = color_rastro.rgb;
	} else {
		ALBEDO = color_fondo.rgb;
	}
}
