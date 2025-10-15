extends CanvasLayer

@onready var life_bar = $MarginContainer/VBoxContainer/LifeBar
@onready var score_label = $MarginContainer/VBoxContainer/ScoreLabel
@onready var combo_label = $ComboLabel
@onready var message_label = $Message
@onready var pause_menu = $PauseMenu
@onready var resume_button = $PauseMenu/VBoxContainer/ResumeButton
@onready var menu_button = $PauseMenu/VBoxContainer/MenuButton
@onready var bg_particles: CPUParticles2D = $CanvasLayer/BGParticles
var combo_tween: Tween

func _ready():
	if combo_label:
		combo_label.modulate.a = 0.0
	
	if message_label:
		message_label.hide()
	
	if pause_menu:
		pause_menu.hide()
	
	# Setup pause menu buttons
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)
	
	if not score_label:
		push_warning("ScoreLabel not found in scene tree!")
	if not life_bar:
		push_warning("LifeBar not found in scene tree!")
	setup_bg_particles()

func setup_bg_particles():
	if bg_particles and bg_particles is CPUParticles2D:
		bg_particles.emitting = true
		bg_particles.amount = 50
		bg_particles.lifetime = 3.0
		bg_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		bg_particles.emission_rect_extents = Vector2(300, 200)
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

func update_life(value, max_value):
	if not life_bar:
		return
	
	life_bar.max_value = max_value
	
	var tween = create_tween()
	tween.tween_property(life_bar, "value", value, 0.2)
	
	var life_percent = value / max_value
	if life_percent > 0.5:
		life_bar.modulate = Color(0.3, 1.0, 0.3)
	elif life_percent > 0.25:
		life_bar.modulate = Color(1.0, 0.8, 0.0)
	else:
		life_bar.modulate = Color(1.0, 0.3, 0.3)
		if life_percent < 0.3:
			pulse_life_bar()

func pulse_life_bar():
	if not life_bar:
		return
	var tween = create_tween()
	tween.tween_property(life_bar, "scale", Vector2(1.05, 1.05), 0.3)
	tween.tween_property(life_bar, "scale", Vector2.ONE, 0.3)

func update_score(current, total):
	if not score_label:
		score_label = get_node_or_null("MarginContainer/VBoxContainer/ScoreLabel")
		if not score_label:
			return
	
	score_label.text = "Souls: %d/%d" % [current, total]
	score_label.pivot_offset = score_label.size / 2
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(score_label, "scale", Vector2(1.3, 1.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	var original_color = score_label.modulate
	tween.tween_property(score_label, "modulate", Color.GOLD, 0.1)
	
	tween.chain().set_parallel(true)
	tween.tween_property(score_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(score_label, "modulate", original_color, 0.2)

func update_combo(combo: int):
	if not combo_label:
		return
	
	combo_label.pivot_offset = combo_label.size / 2
	
	if combo > 1:
		combo_label.text = "x%d COMBO" % combo
		
		if combo_tween:
			combo_tween.kill()
		
		combo_tween = create_tween().set_parallel(true)
		combo_tween.tween_property(combo_label, "modulate:a", 1.0, 0.2)
		combo_tween.tween_property(combo_label, "scale", Vector2(1.3, 1.3), 0.2)
		
		combo_tween.chain()
		combo_tween.tween_property(combo_label, "scale", Vector2.ONE, 0.2)
		
		combo_tween.chain()
		await get_tree().create_timer(1.5).timeout
		if combo_tween:
			combo_tween = create_tween()
			combo_tween.tween_property(combo_label, "modulate:a", 0.0, 0.5)
	else:
		if combo_tween:
			combo_tween.kill()
		combo_tween = create_tween()
		combo_tween.tween_property(combo_label, "modulate:a", 0.0, 0.3)

func show_combo_effect(combo: int):
	if not combo_label:
		return
	
	var color = Color.WHITE
	if combo >= 5:
		color = Color.GOLD
	elif combo >= 3:
		color = Color.ORANGE
	
	combo_label.modulate = color

func show_message(text: String, color := Color.WHITE):
	if not message_label:
		return
	
	message_label.text = text
	message_label.modulate = color
	message_label.modulate.a = 0.0
	message_label.show()
	message_label.pivot_offset = message_label.size / 2
	
	var tween = create_tween()
	tween.tween_property(message_label, "modulate:a", 1.0, 0.5)
	tween.tween_property(message_label, "scale", Vector2(1.2, 1.2), 0.5)

func create_floating_text(text: String, pos: Vector2, color := Color.WHITE):
	var label = Label.new()
	label.text = text
	label.modulate = color
	label.position = pos
	label.z_index = 100
	add_child(label)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", pos.y - 30, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	
	await tween.finished
	label.queue_free()

func show_ignite_popup(pos: Vector2):
	var label = Label.new()
	label.text = "IGNITED!"
	label.modulate = Color.GOLD
	label.scale = Vector2.ZERO
	label.global_position = pos - Vector2(30, 20)
	label.z_index = 100
	
	label.add_theme_font_size_override("font_size", 16)
	label.pivot_offset = label.size / 2
	
	add_child(label)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 1.0, 0.2)
	
	tween.chain().set_parallel(true)
	tween.tween_property(label, "global_position:y", pos.y - 50, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.3)
	
	await tween.finished
	label.queue_free()

func show_pause_menu(visible: bool):
	if pause_menu:
		pause_menu.visible = visible
		if visible and resume_button:
			resume_button.grab_focus()

func _on_resume_pressed():
	var game_manager = get_node_or_null("/root/Game/GameManager")
	if game_manager and game_manager.has_method("toggle_pause"):
		game_manager.toggle_pause()

func _on_menu_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")
