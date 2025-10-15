extends CharacterBody2D

signal soul_ignited
signal soul_extinguished
signal life_changed(current, maximum)
signal started_dash
signal stopped_dash

@export var move_speed := 80.0
@export var dash_speed := 160.0
@export var soul_life := 10.0
@export var life_loss_rate := 1.0
@export var life_restore := 3.0
@export var dash_cooldown := 2.0
@export var low_life_threshold := 3.0
@export var animation_speed := 10.0

# Advanced movement
@export var acceleration := 800.0
@export var friction := 600.0
@export var dodge_iframe_duration := 0.3
@export var aerial_control := 0.8

var current_life : float
var can_dash := true
var is_dashing := false
var dash_direction := Vector2.ZERO
var dash_time := 0.0
var dash_duration := 0.2
var difficulty := 1.0
var animation_frame := 0.0
var invulnerable := false
var invulnerable_timer := 0.0

# Advanced features
var momentum := Vector2.ZERO
var last_direction := Vector2.RIGHT
var dash_charges := 2
var max_dash_charges := 2
var dash_charge_timer := 0.0
var afterimage_timer := 0.0
var skill_cooldowns := {}

@onready var sprite = $Icon
@onready var light = $PointLight2D
@onready var particles = $GlowEffect
@onready var dash_particles = $dash
@onready var shield_particles = $ShieldParticles

func _ready():
	current_life = soul_life
	add_to_group("player")
	setup_visual_effects()
	setup_sprite_animation()
	emit_signal("life_changed", current_life, soul_life)
	
	# Initialize skill cooldowns
	skill_cooldowns = {
		"dash": 0.0,
		"special": 0.0
	}

func setup_sprite_animation():
	if sprite and sprite is Sprite2D:
		sprite.hframes = 4
		sprite.vframes = 1
		sprite.frame = 0

func setup_visual_effects():
	if particles:
		particles.emitting = true
		particles.amount = 15
	if light:
		light.enabled = true
		light.energy = 1.0
		light.texture_scale = 0.5

func _physics_process(delta):
	update_cooldowns(delta)
	
	# Handle invulnerability
	if invulnerable:
		invulnerable_timer -= delta
		if invulnerable_timer <= 0:
			invulnerable = false
			modulate.a = 1.0
		else:
			modulate.a = 0.5 + sin(Time.get_ticks_msec() * 0.02) * 0.3
	
	# Life drain (unless invulnerable)
	if not invulnerable:
		current_life -= life_loss_rate * difficulty * delta
	
	if current_life <= 0:
		emit_signal("soul_extinguished")
		create_death_effect()
		queue_free()
		return
	
	if is_dashing:
		handle_dash(delta)
	else:
		handle_advanced_movement(delta)
	
	animate_sprite(delta)
	emit_signal("life_changed", current_life, soul_life)
	update_visual_state()
	
	# Recharge dash
	if dash_charges < max_dash_charges:
		dash_charge_timer += delta
		if dash_charge_timer >= dash_cooldown:
			dash_charges += 1
			dash_charge_timer = 0.0
			create_charge_effect()

func animate_sprite(delta):
	if sprite and sprite is Sprite2D:
		var speed_multiplier = 1.0
		if velocity.length() > 50:
			speed_multiplier = 2.0
		if is_dashing:
			speed_multiplier = 3.0
		
		animation_frame += animation_speed * speed_multiplier * delta
		sprite.frame = int(animation_frame) % 4

func handle_advanced_movement(delta):
	var input_dir = Vector2.ZERO
	input_dir.x = Input.get_action_strength("right") - Input.get_action_strength("left")
	input_dir.y = Input.get_action_strength("down") - Input.get_action_strength("up")
	
	if input_dir.length() > 0:
		last_direction = input_dir.normalized()
		momentum = momentum.move_toward(last_direction * move_speed, acceleration * delta)
		rotate_towards_movement(last_direction, delta)
	else:
		momentum = momentum.move_toward(Vector2.ZERO, friction * delta)
	
	velocity = momentum
	
	# Dash input
	if Input.is_action_just_pressed("dash") and dash_charges > 0:
		start_dash(last_direction)
	
	# Special ability (hold to charge)
	if Input.is_action_just_pressed("ui_accept") and skill_cooldowns.special <= 0:
		activate_special_ability()
	
	move_and_slide()

func handle_dash(delta):
	dash_time += delta
	
	# Create afterimages
	afterimage_timer += delta
	if afterimage_timer >= 0.05:
		afterimage_timer = 0.0
		create_afterimage()
	
	if dash_time >= dash_duration:
		is_dashing = false
		dash_time = 0.0
		velocity = dash_direction * move_speed
		emit_signal("stopped_dash")
	else:
		velocity = dash_direction * dash_speed
		move_and_slide()

func start_dash(direction: Vector2):
	if dash_charges <= 0:
		return
	
	is_dashing = true
	dash_direction = direction.normalized()
	dash_charges -= 1
	dash_time = 0.0
	afterimage_timer = 0.0
	
	# Invulnerability during dash
	invulnerable = true
	invulnerable_timer = dodge_iframe_duration
	
	emit_signal("started_dash")
	
	var audio_manager = get_node_or_null("/root/Game/GameManager/AudioManager")
	if audio_manager and audio_manager.has_method("play_dash_sound"):
		audio_manager.play_dash_sound()
	
	if dash_particles:
		dash_particles.emitting = true
	
	# Dash animation
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.3, 0.7), 0.1)
	tween.chain()
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)

func activate_special_ability():
	skill_cooldowns.special = 5.0
	
	# Create shockwave that damages nearby enemies
	create_shockwave_pulse()
	
	# Restore some life
	current_life = min(current_life + 2.0, soul_life)
	
	# Visual feedback
	create_special_effect()

func create_shockwave_pulse():
	var pulse = Node2D.new()
	get_tree().root.add_child(pulse)
	pulse.global_position = global_position
	pulse.z_index = 40
	
	var pulse_data = {"radius": 0.0, "alpha": 1.0}
	
	pulse.draw.connect(func():
		pulse.draw_arc(Vector2.ZERO, pulse_data.radius, 0, TAU, 32, 
			Color(0.3, 0.8, 1.0, pulse_data.alpha), 4.0)
	)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_method(func(r): 
		pulse_data.radius = r
		pulse.queue_redraw()
	, 0.0, 200.0, 0.8)
	
	tween.tween_method(func(a): 
		pulse_data.alpha = a
		pulse.queue_redraw()
	, 1.0, 0.0, 0.8)
	
	await tween.finished
	pulse.queue_free()

func create_special_effect():
	var burst = CPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 30
	burst.lifetime = 0.8
	burst.speed_scale = 2.0
	
	burst.direction = Vector2(0, -1)
	burst.spread = 180
	burst.initial_velocity_min = 80.0
	burst.initial_velocity_max = 150.0
	burst.gravity = Vector2(0, 30)
	burst.scale_amount_min = 0.4
	burst.scale_amount_max = 1.0
	
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color.CYAN)
	gradient.add_point(0.5, Color.BLUE)
	gradient.add_point(1.0, Color(0.1, 0.3, 0.8, 0.0))
	burst.color_ramp = gradient
	
	burst.global_position = global_position
	get_tree().root.add_child(burst)
	burst.emitting = true
	
	await get_tree().create_timer(1.0).timeout
	burst.queue_free()

func create_afterimage():
	if not sprite:
		return
	
	var afterimage = Sprite2D.new()
	afterimage.texture = sprite.texture
	afterimage.hframes = sprite.hframes
	afterimage.vframes = sprite.vframes
	afterimage.frame = sprite.frame
	afterimage.global_position = global_position
	afterimage.global_rotation = sprite.global_rotation
	afterimage.scale = sprite.scale * scale
	afterimage.modulate = Color(0.5, 0.8, 1.0, 0.6)
	afterimage.z_index = z_index - 1
	
	get_tree().root.add_child(afterimage)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(afterimage, "modulate:a", 0.0, 0.3)
	tween.tween_property(afterimage, "scale", afterimage.scale * 0.8, 0.3)
	
	await tween.finished
	afterimage.queue_free()

func create_charge_effect():
	var ring = Node2D.new()
	add_child(ring)
	ring.z_index = -1
	
	var ring_data = {"radius": 30.0, "alpha": 0.8}
	
	ring.draw.connect(func():
		ring.draw_arc(Vector2.ZERO, ring_data.radius, 0, TAU, 24, 
			Color(0.3, 1.0, 0.5, ring_data.alpha), 2.0)
	)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_method(func(r): 
		ring_data.radius = r
		ring.queue_redraw()
	, 30.0, 5.0, 0.3)
	
	tween.tween_method(func(a): 
		ring_data.alpha = a
		ring.queue_redraw()
	, 0.8, 0.0, 0.3)
	
	await tween.finished
	ring.queue_free()

func update_cooldowns(delta):
	for skill in skill_cooldowns:
		if skill_cooldowns[skill] > 0:
			skill_cooldowns[skill] -= delta

func rotate_towards_movement(direction: Vector2, delta):
	if sprite:
		var target_rotation = direction.angle() + PI / 2
		sprite.rotation = lerp_angle(sprite.rotation, target_rotation, 10 * delta)

func update_visual_state():
	var life_percent = current_life / soul_life
	
	if not invulnerable:
		modulate.a = clamp(life_percent, 0.3, 1.0)
	
	if current_life < low_life_threshold:
		modulate = Color(1.0, life_percent * 0.5, life_percent * 0.3, modulate.a)
	else:
		modulate = Color(1.0, 1.0, 1.0, modulate.a)
	
	if light:
		light.energy = life_percent * 1.5
		light.texture_scale = 0.3 + life_percent * 0.3
	
	if particles:
		var particle_amount = max(1, int(15 * life_percent))
		particles.amount = particle_amount
		particles.speed_scale = 0.5 + life_percent * 0.5

func restore_life():
	var _old_life = current_life
	current_life = clamp(current_life + life_restore, 0, soul_life)
	emit_signal("soul_ignited")
	emit_signal("life_changed", current_life, soul_life)
	
	create_restore_effect()
	
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("shake"):
		camera.shake(5.0, 0.3)
	
	Engine.time_scale = 0.3
	await get_tree().create_timer(0.15, true, false, true).timeout
	Engine.time_scale = 1.0

func create_restore_effect():
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.2)
	if light:
		tween.tween_property(light, "energy", 3.0, 0.2)
		tween.tween_property(light, "texture_scale", 1.5, 0.2)
	
	tween.chain().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.3)
	if light:
		tween.tween_property(light, "energy", 1.5, 0.3)
		tween.tween_property(light, "texture_scale", 0.5, 0.3)
	
	modulate = Color.GOLD
	await get_tree().create_timer(0.15).timeout
	if not invulnerable:
		modulate = Color(1, 1, 1, modulate.a)
	
	create_ignite_burst()

func create_death_effect():
	if particles:
		particles.emitting = false
	
	# Death explosion
	var explosion = CPUParticles2D.new()
	explosion.emitting = false
	explosion.one_shot = true
	explosion.explosiveness = 1.0
	explosion.amount = 40
	explosion.lifetime = 1.0
	explosion.speed_scale = 2.5
	
	explosion.direction = Vector2(0, -1)
	explosion.spread = 180
	explosion.initial_velocity_min = 100.0
	explosion.initial_velocity_max = 200.0
	explosion.gravity = Vector2(0, 100)
	explosion.scale_amount_min = 0.3
	explosion.scale_amount_max = 1.0
	
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color.RED)
	gradient.add_point(0.5, Color.ORANGE)
	gradient.add_point(1.0, Color(0.5, 0.0, 0.0, 0.0))
	explosion.color_ramp = gradient
	
	explosion.global_position = global_position
	get_tree().root.add_child(explosion)
	explosion.emitting = true

func increase_difficulty(multiplier: float):
	difficulty = multiplier

func get_life_percent() -> float:
	return current_life / soul_life

func add_bonus_life(amount: float):
	current_life = clamp(current_life + amount, 0, soul_life)
	emit_signal("life_changed", current_life, soul_life)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.1)
	if light:
		tween.tween_property(light, "energy", 2.0, 0.1)
	
	tween.chain().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)
	if light:
		tween.tween_property(light, "energy", 1.0, 0.1)
	
	var original_color = modulate
	modulate = Color.CYAN
	await get_tree().create_timer(0.05).timeout
	if not invulnerable:
		modulate = original_color

func create_ignite_burst():
	var burst = CPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 20
	burst.lifetime = 0.6
	burst.speed_scale = 2.0
	
	burst.direction = Vector2(0, -1)
	burst.spread = 180
	burst.initial_velocity_min = 50.0
	burst.initial_velocity_max = 100.0
	burst.gravity = Vector2(0, 50)
	burst.scale_amount_min = 0.3
	burst.scale_amount_max = 0.8
	
	burst.color = Color.GOLD
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color.GOLD)
	gradient.add_point(1.0, Color(1.0, 0.5, 0.0, 0.0))
	burst.color_ramp = gradient
	
	burst.global_position = global_position
	get_tree().root.add_child(burst)
	burst.emitting = true
	
	await get_tree().create_timer(1.0).timeout
	burst.queue_free()

func get_dash_charges() -> int:
	return dash_charges

func get_max_dash_charges() -> int:
	return max_dash_charges
