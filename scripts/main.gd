extends Control

@onready var start_button = $VBoxContainer/StartButton
@onready var quit_button = $VBoxContainer/QuitButton
@onready var title_label = $TitleLabel
@onready var bg_particles = $BGParticles

var title_time := 0.0

func _ready():
	# Setup buttons
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Animate title
	if title_label:
		title_label.pivot_offset = title_label.size / 2
	
	# Setup background particles
	setup_bg_particles()

func setup_bg_particles():
	if bg_particles and bg_particles is CPUParticles2D:
		bg_particles.emitting = true
		bg_particles.amount = 50
		bg_particles.lifetime = 3.0
		bg_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		bg_particles.emission_rect_extents = Vector2(150, 100)
		bg_particles.direction = Vector2(0, -1)
		bg_particles.spread = 30
		bg_particles.gravity = Vector2(0, -20)
		bg_particles.initial_velocity_min = 20.0
		bg_particles.initial_velocity_max = 50.0
		bg_particles.scale_amount_min = 0.3
		bg_particles.scale_amount_max = 0.8
		
		# Gradient color
		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(0.5, 0.7, 1.0, 0.3))
		gradient.add_point(1.0, Color(0.3, 0.5, 0.8, 0.0))
		bg_particles.color_ramp = gradient

func _process(delta):
	title_time += delta
	
	# Animate title with pulse and float
	if title_label:
		var pulse = (sin(title_time * 2) + 1.0) / 2.0
		var float_y = sin(title_time * 1.5) * 5.0
		
		title_label.scale = Vector2.ONE * (1.0 + pulse * 0.1)
		title_label.position.y = title_label.position.y + float_y * delta * 10

func _on_start_pressed():
	play_ui_sound()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_quit_pressed():
	play_ui_sound()
	get_tree().quit()

func play_ui_sound():
	# Simple UI click sound
	var player = AudioStreamPlayer.new()
	add_child(player)
	
	# Generate simple beep
	var stream = AudioStreamGenerator.new()
	stream.mix_rate = 44100
	player.stream = stream
	player.play()
	
	await get_tree().create_timer(0.1).timeout
	player.queue_free()
