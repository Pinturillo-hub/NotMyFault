shader_type spatial;

// --- PARÁMETROS ---
uniform sampler2D textura_paleta : source_color, filter_nearest;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float specular : hint_range(0.0, 1.0) = 0.2;

// Deformación geométrica (Bamboleo)
uniform float deformacion_vertex : hint_range(0.0, 0.05) = 0.005;

// Rugosidad de superficie (Piel de naranja/Arcilla)
uniform float ruido_escala : hint_range(1.0, 100.0) = 50.0;
uniform float ruido_fuerza : hint_range(0.0, 1.0) = 0.1;

// Función de ruido aleatorio simple
float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

void vertex() {
	// Deformación suave para evitar grietas (Tu código anterior arreglado)
	float fuerza = 5.0;
    float velocidad = 2.0;
    float deform_x = sin(VERTEX.y * fuerza + TIME * velocidad);
    float deform_y = cos(VERTEX.x * fuerza + TIME * velocidad);
    float deform_z = sin(VERTEX.z * fuerza + TIME * velocidad);
    
    VERTEX.x += deform_x * deformacion_vertex;
    VERTEX.y += deform_y * deformacion_vertex;
    VERTEX.z += deform_z * deformacion_vertex;
}

void fragment() {
	vec4 color_base = texture(textura_paleta, UV);
	ALBEDO = color_base.rgb;
	
	ROUGHNESS = roughness;
	SPECULAR = specular;
	
	// --- EFECTO RUGOSIDAD (NORMAL MAPPING PROCEDURAL) ---
	// Generamos ruido basado en las coordenadas UV
	float ruido = random(floor(UV * ruido_escala));
	
	// Alteramos la normal (la dirección de la luz) basándonos en el ruido
	// Esto crea la ilusión de granitos o imperfecciones
	vec3 normal_alterada = NORMAL;
	normal_alterada.x += (ruido - 0.5) * ruido_fuerza;
	normal_alterada.y += (ruido - 0.5) * ruido_fuerza;
	
	NORMAL = normalize(normal_alterada);
	
	// Rim Light (Luz de borde) para suavidad
	float fresnel = 1.0 - dot(NORMAL, VIEW);
	fresnel = pow(fresnel, 2.5);
	EMISSION = vec3(0.1) * fresnel;
}