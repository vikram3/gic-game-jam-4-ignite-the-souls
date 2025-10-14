extends CharacterBody2D

signal soul_ignited
signal soul_extinguished
signal life_changed(current, maximum)

@export var move_speed := 80.0
@export var dash_speed := 160.0
@export var soul_life := 10.0
@export var life_loss_rate := 1.0
@export var life_restore := 3.0
@export var dash_cooldown := 2.0
@export var low_life_threshold := 3.0
@export var animation_speed := 10.0

var current_life : float
var can_dash := true
var is_dashing := false
var dash_direction := Vector2.ZERO
var dash_time := 0.0
var dash_duration := 0.2
var difficulty := 1.0
var animation_frame := 0.0

@onready var sprite = $Icon
@onready var light = $PointLight2D
@onready var particles = $GlowEffect
@onready var dash_particles = $dash

func _ready():
	current_life = soul_life
	add_to_group("player")
	setup_visual_effects()
	setup_sprite_animation()
	emit_signal("life_changed", current_life, soul_life)

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
	if current_life <= 0:
		emit_signal("soul_extinguished")
		create_death_effect()
		queue_free()
		return

	if is_dashing:
		handle_dash(delta)
	else:
		handle_movement(delta)
	
	animate_sprite(delta)
	current_life -= life_loss_rate * difficulty * delta
	emit_signal("life_changed", current_life, soul_life)
	update_visual_state()

func animate_sprite(delta):
	if sprite and sprite is Sprite2D:
		var speed_multiplier = 1.0
		if velocity.length() > 50:
			speed_multiplier = 2.0
		if is_dashing:
			speed_multiplier = 3.0
		
		animation_frame += animation_speed * speed_multiplier * delta
		sprite.frame = int(animation_frame) % 4

func handle_movement(delta):
	var input_dir = Vector2.ZERO
	input_dir.x = Input.get_action_strength("right") - Input.get_action_strength("left")
	input_dir.y = Input.get_action_strength("down") - Input.get_action_strength("up")
	
	if input_dir.length() > 0:
		velocity = input_dir.normalized() * move_speed
		rotate_towards_movement(input_dir, delta)
	else:
		velocity = velocity.lerp(Vector2.ZERO, 10 * delta)
	
	if Input.is_action_just_pressed("dash") and can_dash:
		start_dash(input_dir if input_dir.length() > 0 else Vector2.RIGHT)
	
	move_and_slide()

func handle_dash(delta):
	dash_time += delta
	if dash_time >= dash_duration:
		is_dashing = false
		dash_time = 0.0
		velocity = dash_direction * move_speed
	else:
		velocity = dash_direction * dash_speed
		move_and_slide()

func start_dash(direction: Vector2):
	is_dashing = true
	dash_direction = direction.normalized()
	can_dash = false
	dash_time = 0.0
	
	# Play dash sound
	var audio_manager = get_node_or_null("/root/Game/GameManager/AudioManager")
	if audio_manager and audio_manager.has_method("play_dash_sound"):
		audio_manager.play_dash_sound()
	
	if dash_particles:
		dash_particles.emitting = true
	
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.2, 0.8), 0.1)
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)
	
	await get_tree().create_timer(dash_cooldown).timeout
	can_dash = true

func rotate_towards_movement(direction: Vector2, delta):
	if sprite:
		var target_rotation = direction.angle() + PI / 2
		sprite.rotation = lerp_angle(sprite.rotation, target_rotation, 10 * delta)

func update_visual_state():
	var life_percent = current_life / soul_life
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
	modulate = Color(1, 1, 1, modulate.a)
	
	create_ignite_burst()

func create_death_effect():
	if particles:
		particles.emitting = false

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
	
	modulate = Color.CYAN
	await get_tree().create_timer(0.05).timeout
	modulate = Color(1, 1, 1, modulate.a)

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
