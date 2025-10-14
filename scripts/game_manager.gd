extends Node

@onready var player = $"../player_soul"
@onready var souls_container = $"../Souls"
@onready var ui = $"../UI"
@onready var camera = $"../Camera2D"
@onready var audio_manager = $AudioManager

@export var total_souls := 5
@export var spawn_area_margin := 30.0
@export var min_soul_distance := 40.0
@export var world_bounds := Rect2(-100, -50, 400, 250)
@export var chain_reaction_bonus := 2.0

var souls_ignited := 0
var game_over := false
var game_paused := false
var spawn_positions := []
var difficulty_multiplier := 1.0
var combo_count := 0
var last_ignite_time := 0.0
var chain_reaction_count := 0

func _ready():
	setup_camera()
	spawn_souls(total_souls)
	ui.update_score(souls_ignited, total_souls)
	ui.update_combo(0)
	ui.show_pause_menu(false)
	player.soul_ignited.connect(_on_player_ignite)
	player.soul_extinguished.connect(_on_player_dead)
	player.life_changed.connect(_on_player_life_changed)
	
	# Play background music
	if audio_manager:
		audio_manager.play_music()

func setup_camera():
	if camera:
		camera.position = player.position
		camera.enabled = true
		camera.zoom = Vector2(4, 4)  # Adjusted for small window

func _process(_delta):
	# Handle pause input
	if Input.is_action_just_pressed("ui_cancel") and not game_over:
		toggle_pause()
	
	if camera and player and not game_paused:
		camera.position = lerp(camera.position, player.position, 0.1)

func toggle_pause():
	game_paused = !game_paused
	get_tree().paused = game_paused
	ui.show_pause_menu(game_paused)
	
	if audio_manager:
		if game_paused:
			audio_manager.pause_music()
		else:
			audio_manager.resume_music()

func spawn_souls(amount):
	var scene = preload("res://scenes/soul.tscn")
	spawn_positions.clear()
	
	for i in range(amount):
		var attempts = 0
		var valid_pos = false
		var soul_pos = Vector2.ZERO
		
		while not valid_pos and attempts < 100:
			soul_pos = Vector2(
				randf_range(world_bounds.position.x, world_bounds.position.x + world_bounds.size.x),
				randf_range(world_bounds.position.y, world_bounds.position.y + world_bounds.size.y)
			)
			
			if soul_pos.distance_to(player.position) < spawn_area_margin:
				attempts += 1
				continue
			
			valid_pos = true
			for pos in spawn_positions:
				if soul_pos.distance_to(pos) < min_soul_distance:
					valid_pos = false
					break
			
			attempts += 1
		
		if valid_pos:
			var soul = scene.instantiate()
			soul.position = soul_pos
			soul.set_difficulty(difficulty_multiplier)
			souls_container.add_child(soul)
			spawn_positions.append(soul_pos)
			print("Soul spawned at: ", soul_pos)
		else:
			print("Failed to spawn soul ", i, " after ", attempts, " attempts")

func _on_player_ignite():
	souls_ignited += 1
	
	# Play ignite sound
	if audio_manager:
		audio_manager.play_ignite_sound()
	
	if ui.has_method("show_ignite_popup"):
		ui.show_ignite_popup(player.global_position)
	
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_ignite_time < 3.0:
		combo_count += 1
		ui.show_combo_effect(combo_count)
		if audio_manager:
			audio_manager.play_combo_sound(combo_count)
	else:
		combo_count = 1
	last_ignite_time = current_time
	
	ui.update_score(souls_ignited, total_souls)
	ui.update_combo(combo_count)
	
	difficulty_multiplier += 0.1
	player.increase_difficulty(difficulty_multiplier)
	
	if souls_ignited >= total_souls:
		win_game()

func win_game():
	ui.show_message("✨ You Ignited All Souls ✨", Color.GOLD)
	game_over = true
	player.set_physics_process(false)
	
	if audio_manager:
		audio_manager.play_victory_sound()
	
	await get_tree().create_timer(3.0).timeout
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_player_dead():
	if not game_over:
		ui.show_message("💀 Your Soul Faded Away 💀", Color.RED)
		game_over = true
		
		if audio_manager:
			audio_manager.play_death_sound()
		
		await get_tree().create_timer(2.0).timeout
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_player_life_changed(current, maximum):
	ui.update_life(current, maximum)
	
	# Play low health warning sound
	if audio_manager and current < maximum * 0.3:
		audio_manager.play_low_health_sound()
