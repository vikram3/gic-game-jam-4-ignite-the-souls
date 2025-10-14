shader_type canvas_item;

uniform float flame_speed = 2.0;
uniform float flame_intensity = 1.5;
uniform float distortion_strength = 0.05;
uniform vec4 fire_color_hot : source_color = vec4(1.0, 0.9, 0.3, 1.0);
uniform vec4 fire_color_mid : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform vec4 fire_color_cool : source_color = vec4(0.8, 0.2, 0.05, 1.0);
uniform float glow_strength = 2.0;
uniform float ember_count = 30.0;

// Simple noise function
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal noise
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for(int i = 0; i < 5; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

void fragment() {
    vec2 uv = UV;
    vec4 tex_color = texture(TEXTURE, uv);
    
    // Only process visible pixels (text)
    if (tex_color.a > 0.1) {
        // Create flame movement
        float time = TIME * flame_speed;
        
        // Distortion for heat wave effect
        vec2 distorted_uv = uv;
        distorted_uv.x += sin(uv.y * 10.0 + time * 2.0) * distortion_strength;
        distorted_uv.y += cos(uv.x * 8.0 + time * 3.0) * distortion_strength * 0.5;
        
        // Flame pattern - rises from bottom
        float flame_noise = fbm(vec2(distorted_uv.x * 5.0, distorted_uv.y * 3.0 - time));
        float vertical_gradient = 1.0 - uv.y; // Flames stronger at bottom
        float flame = flame_noise * vertical_gradient * flame_intensity;
        
        // Create flickering effect
        float flicker = sin(time * 5.0) * 0.1 + 0.9;
        flame *= flicker;
        
        // Color gradient based on flame intensity
        vec3 fire_color;
        if (flame > 0.7) {
            fire_color = mix(fire_color_mid.rgb, fire_color_hot.rgb, (flame - 0.7) / 0.3);
        } else if (flame > 0.3) {
            fire_color = mix(fire_color_cool.rgb, fire_color_mid.rgb, (flame - 0.3) / 0.4);
        } else {
            fire_color = fire_color_cool.rgb * (flame / 0.3);
        }
        
        // Add embers/sparks
        float ember_size = 0.003;
        for(float i = 0.0; i < ember_count; i++) {
            vec2 ember_pos = vec2(
                hash(vec2(i, 1.0)),
                fract(hash(vec2(i, 2.0)) - time * 0.2)
            );
            
            float dist = distance(uv, ember_pos);
            if (dist < ember_size) {
                float ember_brightness = (1.0 - dist / ember_size);
                fire_color += fire_color_hot.rgb * ember_brightness * 2.0;
            }
        }
        
        // Edge glow
        float edge_detection = 1.0 - smoothstep(0.0, 0.1, tex_color.a);
        vec3 edge_glow = fire_color_hot.rgb * edge_detection * glow_strength;
        
        // Combine everything
        vec3 final_color = mix(tex_color.rgb, fire_color, 0.8);
        final_color += edge_glow;
        
        // Brighten the overall effect
        final_color *= 1.5;
        
        // Pulsing brightness
        float pulse = sin(time * 3.0) * 0.15 + 1.0;
        final_color *= pulse;
        
        COLOR = vec4(final_color, tex_color.a);
    } // This closing brace was missing
}