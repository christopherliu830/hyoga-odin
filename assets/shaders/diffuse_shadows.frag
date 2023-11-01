#version 450

layout(set = 0, binding = 1) uniform Lights {
    vec4 direction;
    vec4 color;
} _light;

layout(set = 0, binding = 2) uniform sampler2D _shadow_map;

layout(set = 2, binding = 0) uniform MaterialBuffer {
    vec4 color;
} _material;

layout(location = 0) in vec3 fragNormal;
layout(location = 1) in vec3 fragLightDir;
layout(location = 2) in vec3 fragShadowCoords;

layout(location = 0) out vec4 outColor;

float calcShadowFactor(){
	// perspective divide
	/*
	//float deno = 1.0 / fragShadowCoords.w;
	//vec3 proj_coords = fragShadowCoords.xyz * deno;
	vec3 proj_coords = fragShadowCoords;
	vec2 shadow_uv;	
	shadow_uv.x = 0.5 * proj_coords.x + 0.5;
	shadow_uv.y = 0.5 * proj_coords.y + 0.5;
	float z = 0.5 * proj_coords.z + 0.5;
	float depth = texture(_shadow_map, shadow_uv).x;
	*/
	float z = fragShadowCoords.z;
	float depth = texture(_shadow_map, fragShadowCoords.xy).x;
	if(depth < (z + 0.00001))
		return 0.5;
	else
		return 1.0;
}

void main() {
	float shadow_factor = calcShadowFactor();
    vec3 normal = normalize(fragNormal);
    vec3 lightDir = normalize(-fragLightDir);

    float ambient_const = 0.05;
    vec3 ambient = vec3(ambient_const, ambient_const, ambient_const) * _material.color.xyz;
	
    float diff = clamp(dot(normal, lightDir), 0.0, 1.0);
    vec3 diffuse = _material.color.xyz * _light.color.xyz * diff * shadow_factor;

    vec3 result = clamp(ambient + diffuse, 0.0, 1.0);

    outColor = vec4(result, 1.0);
}


