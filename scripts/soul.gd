extends Area2D

@onready var sprite = $Icon
@onready var light = $PointLight2D
@onready var particles = $CPUParticles2D

@export var glow_strength := 0.5
@export var pulse_speed := 2.0
@export var float_amplitude := 3.0
@export var float_speed := 1.5
@export var animation_speed := 8.0
@export var chain_reaction_range := 200.0
@export var chain_reaction_delay := 0.2

# Soul type properties
@export_enum("Life", "Mana", "Spirit", "Dark", "Ancient", "Chaos") var soul_type := 0
@export var custom_color : Color = Color.TRANSPARENT
@export var randomize_type_on_spawn := true  # New: Enable random soul types
@export var spawn_weights : Array[float] = [1.0, 1.0, 1.0, 1.0, 0.3, 0.1]  # Weights for each soul type

var time := 0.0
var initial_y := 0.0
var difficulty := 1.0
var detection_range := 40.0
var player_nearby := false
var animation_frame := 0.0
var is_being_collected := false
var ignited_by_chain := false

# Fire shader properties
var fire_shader_material: ShaderMaterial
var burn_tween: Tween

# Soul type definitions
var soul_types = {
	"Life": {
		"color": Color.from_hsv(0.3, 0.8, 1.0),  # Green
		"light_color": Color(0.3, 1.0, 0.4, 1.0),
		"particle_color": Color(0.4, 1.0, 0.5, 0.8),
		"fire_color_hot": Color(0.8, 1.0, 0.3, 1.0),
		"fire_color_mid": Color(0.4, 0.9, 0.2, 1.0),
		"fire_color_cool": Color(0.2, 0.6, 0.1, 1.0),
		"glow_multiplier": 1.2
	},
	"Mana": {
		"color": Color.from_hsv(0.6, 0.8, 1.0),  # Blue
		"light_color": Color(0.3, 0.5, 1.0, 1.0),
		"particle_color": Color(0.4, 0.6, 1.0, 0.8),
		"fire_color_hot": Color(0.3, 0.8, 1.0, 1.0),
		"fire_color_mid": Color(0.1, 0.5, 0.9, 1.0),
		"fire_color_cool": Color(0.05, 0.3, 0.7, 1.0),
		"glow_multiplier": 1.5
	},
	"Spirit": {
		"color": Color.from_hsv(0.8, 0.7, 1.0),  # Purple
		"light_color": Color(0.7, 0.3, 1.0, 1.0),
		"particle_color": Color(0.8, 0.4, 1.0, 0.8),
		"fire_color_hot": Color(0.9, 0.4, 1.0, 1.0),
		"fire_color_mid": Color(0.7, 0.2, 0.8, 1.0),
		"fire_color_cool": Color(0.5, 0.1, 0.6, 1.0),
		"glow_multiplier": 1.8
	},
	"Dark": {
		"color": Color.from_hsv(0.15, 0.9, 0.8),  # Dark Orange/Brown
		"light_color": Color(0.8, 0.3, 0.1, 1.0),
		"particle_color": Color(0.9, 0.4, 0.2, 0.8),
		"fire_color_hot": Color(1.0, 0.5, 0.1, 1.0),
		"fire_color_mid": Color(0.8, 0.3, 0.05, 1.0),
		"fire_color_cool": Color(0.6, 0.2, 0.0, 1.0),
		"glow_multiplier": 0.8
	},
	"Ancient": {
		"color": Color.from_hsv(0.1, 0.6, 0.9),  # Gold
		"light_color": Color(1.0, 0.8, 0.3, 1.0),
		"particle_color": Color(1.0, 0.9, 0.4, 0.8),
		"fire_color_hot": Color(1.0, 1.0, 0.5, 1.0),
		"fire_color_mid": Color(1.0, 0.7, 0.2, 1.0),
		"fire_color_cool": Color(0.8, 0.5, 0.1, 1.0),
		"glow_multiplier": 2.0
	},
	"Chaos": {
		"color": Color.from_hsv(0.0, 0.9, 1.0),  # Will change over time in _process
		"light_color": Color(1.0, 0.5, 0.5, 1.0),
		"particle_color": Color(1.0, 0.6, 0.6, 0.8),
		"fire_color_hot": Color(1.0, 0.3, 0.3, 1.0),
		"fire_color_mid": Color(0.8, 0.1, 0.8, 1.0),
		"fire_color_cool": Color(0.3, 0.1, 1.0, 1.0),
		"glow_multiplier": 1.3
	}
}

func _ready():
	connect("body_entered", _on_body_entered)
	initial_y = position.y
	setup_sprite_animation()
	setup_visual_effects()
	setup_fire_shader()
	
	# Randomize soul type if enabled
	if randomize_type_on_spawn:
		randomize_soul_type()
	
	apply_soul_type()
	randomize_appearance()

func randomize_soul_type():
	# Use weighted random selection
	var total_weight = 0.0
	for i in range(spawn_weights.size()):
		total_weight += spawn_weights[i]
	
	var random_value = randf() * total_weight
	var cumulative_weight = 0.0
	
	for i in range(spawn_weights.size()):
		cumulative_weight += spawn_weights[i]
		if random_value <= cumulative_weight:
			soul_type = i
			break

func setup_sprite_animation():
	if sprite and sprite is Sprite2D:
		sprite.hframes = 4
		sprite.vframes = 1
		sprite.frame = 0

func setup_visual_effects():
	if light:
		light.enabled = true
		light.energy = 0.6
		light.texture_scale = 0.3
	
	if particles:
		particles.emitting = true
		particles.amount = 6
		particles.lifetime = 1.0
		particles.scale_amount_min = 0.2
		particles.scale_amount_max = 0.4

func setup_fire_shader():
	# Create fire shader material
	fire_shader_material = ShaderMaterial.new()
	fire_shader_material.shader = preload("res://scenes/Title.gdshader") # Replace with your shader path
	
	# Set initial shader properties
	fire_shader_material.set_shader_parameter("flame_speed", 2.0)
	fire_shader_material.set_shader_parameter("flame_intensity", 0.0) # Start with no fire
	fire_shader_material.set_shader_parameter("distortion_strength", 0.03)
	fire_shader_material.set_shader_parameter("glow_strength", 1.5)
	
	# Apply shader to sprite
	if sprite:
		sprite.material = fire_shader_material

func apply_soul_type():
	var type_keys = soul_types.keys()
	if soul_type >= type_keys.size():
		soul_type = 0
	
	var current_type = type_keys[soul_type]
	var soul_data = soul_types[current_type]
	
	# Apply custom color if set
	if custom_color != Color.TRANSPARENT:
		modulate = custom_color
		if light:
			light.color = custom_color
		if particles:
			particles.color = custom_color
	else:
		# Apply type-based colors
		modulate = soul_data.color
		if light:
			light.color = soul_data.light_color
			light.energy *= soul_data.glow_multiplier
		if particles:
			particles.color = soul_data.particle_color
	
	# Update fire shader colors if available
	if fire_shader_material:
		fire_shader_material.set_shader_parameter("fire_color_hot", soul_data.fire_color_hot)
		fire_shader_material.set_shader_parameter("fire_color_mid", soul_data.fire_color_mid)
		fire_shader_material.set_shader_parameter("fire_color_cool", soul_data.fire_color_cool)

func randomize_appearance():
	# Apply slight variations based on type
	var type_keys = soul_types.keys()
	var current_type = type_keys[soul_type]
	var soul_data = soul_types[current_type]
	
	var hue_shift = randf_range(-0.05, 0.05)
	var sat_shift = randf_range(-0.1, 0.1)
	var val_shift = randf_range(-0.1, 0.1)
	
	if custom_color == Color.TRANSPARENT:
		var base_color = soul_data.color
		var shifted_color = Color.from_hsv(
			base_color.h + hue_shift,
			clamp(base_color.s + sat_shift, 0.3, 1.0),
			clamp(base_color.v + val_shift, 0.6, 1.0)
		)
		modulate = shifted_color
	
	time = randf_range(0, TAU)
	
	var scale_var = randf_range(0.9, 1.1)
	scale = Vector2(scale_var, scale_var)
	
	# Randomize animation speed slightly
	animation_speed *= randf_range(0.8, 1.2)
	
	# Randomize float properties for more natural movement
	float_amplitude *= randf_range(0.8, 1.2)
	float_speed *= randf_range(0.8, 1.2)

func _process(delta):
	time += delta
	
	# Handle Chaos soul color changing
	if soul_type == 5:  # Chaos type
		var chaos_color = Color.from_hsv(time * 0.5, 0.9, 1.0)
		modulate = chaos_color
		if light:
			light.color = chaos_color
		if particles:
			particles.color = chaos_color.lightened(0.2)
	
	animate_sprite(delta)
	
	var float_offset = sin(time * float_speed) * float_amplitude
	position.y = initial_y + float_offset
	
	var pulse = (sin(time * pulse_speed) + 1.0) / 2.0
	if light:
		light.energy = 0.4 + pulse * 0.3
		light.texture_scale = 0.25 + pulse * 0.15
	
	if sprite:
		sprite.rotation = sin(time * 0.5) * 0.2
	
	check_player_proximity()
	
	# Update shader time
	if fire_shader_material:
		fire_shader_material.set_shader_parameter("time", time)

func animate_sprite(delta):
	if sprite and sprite is Sprite2D:
		var speed_mult = 1.0
		if player_nearby:
			speed_mult = 2.0
		
		animation_frame += animation_speed * speed_mult * delta
		sprite.frame = int(animation_frame) % 4

func check_player_proximity():
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var distance = global_position.distance_to(player.global_position)
		player_nearby = distance < detection_range
		
		if player_nearby:
			var attract_pulse = (sin(time * 4) + 1.0) / 2.0
			if light:
				light.energy = 0.7 + attract_pulse * 0.4
			
			if particles:
				var dir_to_player = (player.global_position - global_position).normalized()
				particles.gravity = dir_to_player * 30
				particles.amount = 8
		else:
			if particles:
				particles.amount = 6
				particles.gravity = Vector2.ZERO

func _on_body_entered(body):
	if body.is_in_group("player"):
		# Different effects based on soul type
		match soul_type:
			0: # Life - restore health
				body.restore_life()
			1: # Mana - restore mana or special ability
				if body.has_method("restore_mana"):
					body.restore_mana()
				else:
					body.restore_life()
			2: # Spirit - temporary buff
				if body.has_method("apply_spirit_buff"):
					body.apply_spirit_buff()
				else:
					body.restore_life()
			3: # Dark - different effect
				if body.has_method("apply_dark_effect"):
					body.apply_dark_effect()
				else:
					body.restore_life()
			4: # Ancient - special effect
				if body.has_method("apply_ancient_power"):
					body.apply_ancient_power()
				else:
					body.restore_life()
			5: # Chaos - random effect
				if body.has_method("apply_chaos_effect"):
					body.apply_chaos_effect()
				else:
					body.restore_life()
		
		start_burn_effect()

func start_burn_effect():
	if is_being_collected:
		return
	
	is_being_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# Stop normal animations
	if sprite:
		sprite.frame = 0
	
	# Start burn sequence
	await apply_fire_effect()
	await create_burn_expansion()
	await create_final_ignition()
	
	# Now destroy the object
	queue_free()

func apply_fire_effect():
	# Tween the fire intensity from 0 to maximum
	burn_tween = create_tween().set_parallel(true)
	
	# Increase fire intensity gradually
	burn_tween.tween_method(_update_fire_intensity, 0.0, 3.0, 0.8)
	
	# Add color shift to fiery colors based on soul type
	if sprite:
		var type_keys = soul_types.keys()
		var current_type = type_keys[soul_type]
		var soul_data = soul_types[current_type]
		var target_color = soul_data.fire_color_mid.lightened(0.3)
		burn_tween.tween_property(sprite, "modulate", target_color, 0.6)
	
	# Increase light intensity
	if light:
		burn_tween.tween_property(light, "energy", 2.0, 0.8)
		burn_tween.tween_property(light, "texture_scale", 1.5, 0.8)
	
	await burn_tween.finished

func _update_fire_intensity(intensity: float):
	if fire_shader_material:
		fire_shader_material.set_shader_parameter("flame_intensity", intensity)
		fire_shader_material.set_shader_parameter("glow_strength", intensity * 0.8)

func create_burn_expansion():
	# Create burning particle effect
	if particles:
		particles.emitting = false
		particles.explosiveness = 0.8
		particles.amount = 20
		particles.lifetime = 1.2
		particles.speed_scale = 1.8
		particles.initial_velocity_min = 40.0
		particles.initial_velocity_max = 100.0
		particles.spread = 180
		particles.direction = Vector2(0, -1)
		particles.gravity = Vector2(0, -50)
		particles.emitting = true
	
	# Scale and distort the sprite
	var burn_tween2 = create_tween().set_parallel(true)
	
	if sprite:
		burn_tween2.tween_property(sprite, "scale", 
			Vector2(1.3, 1.3), 0.4)
		burn_tween2.tween_property(sprite, "rotation", 
			randf_range(-0.5, 0.5), 0.4)
	
	# Increase shader distortion
	if fire_shader_material:
		burn_tween2.tween_method(_update_distortion, 0.03, 0.1, 0.4)
	
	await burn_tween2.finished

func _update_distortion(strength: float):
	if fire_shader_material:
		fire_shader_material.set_shader_parameter("distortion_strength", strength)

func create_final_ignition():
	# Final intense burn before disappearance
	var final_tween = create_tween().set_parallel(true)
	
	# Maximum fire intensity
	if fire_shader_material:
		final_tween.tween_method(_update_fire_intensity, 3.0, 5.0, 0.3)
	
	# Bright flash
	if light:
		final_tween.tween_property(light, "energy", 4.0, 0.2)
		final_tween.tween_property(light, "texture_scale", 2.5, 0.3)
	
	# Fade out
	if sprite:
		final_tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	
	# Final particle burst
	if particles:
		particles.one_shot = true
		particles.amount = 50
		particles.explosiveness = 1.0
		particles.speed_scale = 3.0
		particles.initial_velocity_min = 80.0
		particles.initial_velocity_max = 200.0
		particles.emitting = true
	
	await final_tween.finished

func create_shockwave():
	var shockwave = Node2D.new()
	get_tree().root.add_child(shockwave)
	shockwave.global_position = global_position
	shockwave.z_index = 10
	
	# Use arrays to store values that need to be modified in lambdas
	var shockwave_data = {
		"radius": 0.0,
		"alpha": 1.0
	}
	
	var max_radius = 80.0
	
	shockwave.draw.connect(func():
		shockwave.draw_arc(Vector2.ZERO, shockwave_data.radius, 0, TAU, 24, Color(1, 0.8, 0.3, shockwave_data.alpha), 2.0)
	)
	
	var tween = create_tween().set_parallel(true)
	
	# Tween the radius using the shockwave_data dictionary
	tween.tween_method(func(r): 
		shockwave_data.radius = r
		shockwave.queue_redraw()
	, 0.0, max_radius, 0.4)
	
	# Tween the alpha using the shockwave_data dictionary
	tween.tween_method(func(a): 
		shockwave_data.alpha = a
		shockwave.queue_redraw()
	, 1.0, 0.0, 0.4)
	
	await tween.finished
	shockwave.queue_free()

func set_difficulty(multiplier: float):
	difficulty = multiplier
	animation_speed = 8.0 + (multiplier - 1.0) * 3.0

# Public method to set soul type programmatically
func set_soul_type(type: int):
	soul_type = type
	apply_soul_type()

# Public method to set custom color
func set_custom_color(color: Color):
	custom_color = color
	apply_soul_type()

# Public method to force random soul type
func randomize_soul_type_manual():
	randomize_soul_type()
	apply_soul_type()
