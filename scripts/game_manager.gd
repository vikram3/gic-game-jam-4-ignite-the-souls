extends Node

@onready var player = $"../player_soul"
@onready var souls_container = $"../Souls"
@onready var ui = $"../UI"
@onready var camera = $"../Camera2D"
@onready var audio_manager = $AudioManager

@export var total_souls := 100
@export var spawn_area_margin := 30.0
@export var min_soul_distance := 40.0
@export var world_bounds := Rect2(-200, -150, 800, 500)
@export var chain_reaction_bonus := 2.0
@export var near_player_souls := 3
@export var near_player_radius := 80.0
@export var waypoint_threshold := 15
@export var chain_ignition_threshold := 20
@export var chain_ignition_range := 120.0

# Advanced features
@export var dynamic_difficulty := true
@export var soul_magnetism := true
@export var magnetism_range := 150.0
@export var time_slow_on_combo := true
@export var screen_shake_on_combo := true

var souls_ignited := 0
var game_over := false
var game_paused := false
var spawn_positions := []
var difficulty_multiplier := 1.0
var combo_count := 0
var last_ignite_time := 0.0
var chain_reaction_count := 0
var waypoints_active := false
var waypoint_markers := []
var souls_since_last_chain := 0
var chain_reaction_souls := []

# Advanced tracking
var highest_combo := 0
var total_time := 0.0
var score_multiplier := 1.0
var power_up_active := false
var power_up_timer := 0.0
var souls_magnetic := []
var performance_stats := {
	"ignites_per_second": 0.0,
	"average_combo": 0.0,
	"chain_reactions_triggered": 0
}

func _ready():
	setup_camera()
	spawn_souls(total_souls)
	ui.update_score(souls_ignited, total_souls)
	ui.update_combo(0)
	ui.show_pause_menu(false)
	player.soul_ignited.connect(_on_player_ignite)
	player.soul_extinguished.connect(_on_player_dead)
	player.life_changed.connect(_on_player_life_changed)
	
	if audio_manager:
		audio_manager.play_music()

func setup_camera():
	if camera:
		camera.position = player.position
		camera.enabled = true
		camera.zoom = Vector2(3.5, 3.5)

func _process(delta):
	total_time += delta
	
	if Input.is_action_just_pressed("ui_cancel") and not game_over:
		toggle_pause()
	
	if camera and player and not game_paused:
		camera.position = lerp(camera.position, player.position, 0.1)
	
	if waypoints_active:
		update_waypoint_markers()
	
	# Update power-up timer
	if power_up_active:
		power_up_timer -= delta
		if power_up_timer <= 0:
			deactivate_power_up()
	
	# Apply soul magnetism
	if soul_magnetism and not game_paused:
		apply_soul_magnetism(delta)
	
	# Dynamic difficulty adjustment
	if dynamic_difficulty and total_time > 10.0:
		adjust_dynamic_difficulty()

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
	var souls_spawned = 0
	
	for i in range(min(near_player_souls, amount)):
		var soul_pos = find_valid_spawn_position(true)
		if soul_pos != Vector2.ZERO:
			create_soul(scene, soul_pos)
			souls_spawned += 1
	
	for i in range(souls_spawned, amount):
		var soul_pos = find_valid_spawn_position(false)
		if soul_pos != Vector2.ZERO:
			create_soul(scene, soul_pos)
		else:
			print("Failed to spawn soul ", i)

func find_valid_spawn_position(near_player: bool) -> Vector2:
	var attempts = 0
	var max_attempts = 150
	
	while attempts < max_attempts:
		var soul_pos = Vector2.ZERO
		
		if near_player:
			var angle = randf() * TAU
			var distance = randf_range(spawn_area_margin + 10, near_player_radius)
			soul_pos = player.position + Vector2(cos(angle), sin(angle)) * distance
		else:
			soul_pos = Vector2(
				randf_range(world_bounds.position.x, world_bounds.position.x + world_bounds.size.x),
				randf_range(world_bounds.position.y, world_bounds.position.y + world_bounds.size.y)
			)
		
		if not world_bounds.has_point(soul_pos):
			attempts += 1
			continue
		
		if not near_player and soul_pos.distance_to(player.position) < spawn_area_margin:
			attempts += 1
			continue
		
		var valid_pos = true
		for pos in spawn_positions:
			if soul_pos.distance_to(pos) < min_soul_distance:
				valid_pos = false
				break
		
		if valid_pos:
			spawn_positions.append(soul_pos)
			return soul_pos
		
		attempts += 1
	
	return Vector2.ZERO

func create_soul(scene: PackedScene, pos: Vector2):
	var soul = scene.instantiate()
	soul.position = pos
	soul.set_difficulty(difficulty_multiplier)
	souls_container.add_child(soul)

func _on_player_ignite():
	souls_ignited += 1
	souls_since_last_chain += 1
	
	if audio_manager:
		audio_manager.play_ignite_sound()
	
	if ui.has_method("show_ignite_popup"):
		ui.show_ignite_popup(player.global_position)
	
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_ignite_time < 3.0:
		combo_count += 1
		
		# Enhanced combo feedback
		if combo_count > highest_combo:
			highest_combo = combo_count
		
		ui.show_combo_effect(combo_count)
		if audio_manager:
			audio_manager.play_combo_sound(combo_count)
		
		# Time slow effect on high combos
		if time_slow_on_combo and combo_count >= 5:
			apply_time_slow(0.7, 0.5)
		
		# Screen shake on combos
		if screen_shake_on_combo and camera and camera.has_method("shake"):
			camera.shake(2.0 + combo_count * 0.5, 0.2)
		
		# Bonus multiplier
		score_multiplier = 1.0 + (combo_count * 0.1)
		
		# Special rewards at combo milestones
		if combo_count == 10:
			activate_power_up("speed_boost", 5.0)
		elif combo_count == 20:
			activate_power_up("invincibility", 3.0)
	else:
		combo_count = 1
		score_multiplier = 1.0
	
	last_ignite_time = current_time
	
	ui.update_score(souls_ignited, total_souls)
	ui.update_combo(combo_count)
	
	difficulty_multiplier += 0.05
	player.increase_difficulty(difficulty_multiplier)
	
	if souls_since_last_chain >= chain_ignition_threshold:
		trigger_chain_reaction(player.global_position)
		souls_since_last_chain = 0
	
	var remaining_souls = total_souls - souls_ignited
	if remaining_souls <= waypoint_threshold and not waypoints_active:
		activate_waypoints()
	
	if souls_ignited >= total_souls:
		win_game()

func apply_time_slow(scale: float, duration: float):
	Engine.time_scale = scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

func activate_power_up(type: String, duration: float):
	power_up_active = true
	power_up_timer = duration
	
	match type:
		"speed_boost":
			player.move_speed *= 1.5
			if ui.has_method("show_message"):
				ui.show_message("⚡ SPEED BOOST! ⚡", Color.CYAN)
		"invincibility":
			player.life_loss_rate = 0.0
			if ui.has_method("show_message"):
				ui.show_message("🛡️ INVINCIBLE! 🛡️", Color.GOLD)

func deactivate_power_up():
	power_up_active = false
	player.move_speed = 80.0
	player.life_loss_rate = 1.0

func apply_soul_magnetism(delta):
	var souls = souls_container.get_children()
	
	for soul in souls:
		if not is_instance_valid(soul):
			continue
		
		var distance = soul.global_position.distance_to(player.global_position)
		
		if distance < magnetism_range:
			var attract_force = 1.0 - (distance / magnetism_range)
			var direction = (player.global_position - soul.global_position).normalized()
			var pull_strength = attract_force * attract_force * 100.0 * delta
			
			soul.global_position += direction * pull_strength
			
			# Visual feedback
			if soul.has_method("set_magnetic_effect"):
				soul.set_magnetic_effect(true)
		elif soul.has_method("set_magnetic_effect"):
			soul.set_magnetic_effect(false)

func adjust_dynamic_difficulty():
	var performance = souls_ignited / total_time
	
	if performance > 1.5:
		difficulty_multiplier = min(difficulty_multiplier + 0.01, 3.0)
	elif performance < 0.5:
		difficulty_multiplier = max(difficulty_multiplier - 0.01, 0.5)

func activate_waypoints():
	waypoints_active = true
	print("Waypoints activated! ", total_souls - souls_ignited, " souls remaining")

func trigger_chain_reaction(origin: Vector2):
	var souls = souls_container.get_children()
	chain_reaction_souls.clear()
	
	for soul in souls:
		if not is_instance_valid(soul):
			continue
		
		var distance = soul.global_position.distance_to(origin)
		if distance <= chain_ignition_range and distance > 0:
			chain_reaction_souls.append(soul)
	
	if chain_reaction_souls.size() > 0:
		performance_stats.chain_reactions_triggered += 1
		print("🔥 CHAIN REACTION! ", chain_reaction_souls.size(), " souls affected")
		
		if ui and ui.has_method("show_message"):
			ui.show_message("🔥 CHAIN REACTION x%d! 🔥" % chain_reaction_souls.size(), Color.ORANGE_RED)
		
		create_screen_flash(Color(1.0, 0.5, 0.0, 0.3))
		if camera and camera.has_method("shake"):
			camera.shake(8.0, 0.5)
		
		start_chain_sequence()
		
		await get_tree().create_timer(1.5).timeout
		if ui and ui.has_method("show_message"):
			ui.show_message("", Color.WHITE)

func start_chain_sequence():
	create_chain_explosion_ring(player.global_position)
	
	for i in range(chain_reaction_souls.size()):
		var soul = chain_reaction_souls[i]
		if is_instance_valid(soul):
			await get_tree().create_timer(0.08).timeout
			ignite_soul_by_chain(soul)

func ignite_soul_by_chain(soul):
	if not is_instance_valid(soul):
		return
	
	souls_ignited += 1
	combo_count += 1
	
	create_chain_lightning(player.global_position, soul.global_position)
	
	if player.has_method("add_bonus_life"):
		player.add_bonus_life(0.5)
	
	ui.update_score(souls_ignited, total_souls)
	ui.update_combo(combo_count)
	
	if audio_manager:
		audio_manager.play_combo_sound(combo_count)
	
	if soul.has_method("start_burn_effect"):
		soul.start_burn_effect()
	else:
		soul.queue_free()

func create_chain_explosion_ring(origin: Vector2):
	var ring = Node2D.new()
	get_tree().root.add_child(ring)
	ring.global_position = origin
	ring.z_index = 50
	
	var ring_data = {"radius": 0.0, "alpha": 0.8, "thickness": 3.0}
	
	ring.draw.connect(func():
		ring.draw_arc(Vector2.ZERO, ring_data.radius, 0, TAU, 48, 
			Color(1.0, 0.6, 0.0, ring_data.alpha), ring_data.thickness)
	)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_method(func(r): 
		ring_data.radius = r
		ring.queue_redraw()
	, 0.0, chain_ignition_range, 0.6)
	
	tween.tween_method(func(a): 
		ring_data.alpha = a
		ring.queue_redraw()
	, 0.8, 0.0, 0.6)
	
	await tween.finished
	ring.queue_free()

func create_chain_lightning(from: Vector2, to: Vector2):
	var lightning = Line2D.new()
	get_tree().root.add_child(lightning)
	lightning.z_index = 45
	lightning.width = 2.0
	lightning.default_color = Color(1.0, 0.8, 0.2, 0.9)
	
	var points = PackedVector2Array()
	var segments = 8
	var direction = (to - from)
	var distance = direction.length()
	direction = direction.normalized()
	
	points.append(from)
	for i in range(1, segments):
		var t = float(i) / segments
		var point = from + direction * distance * t
		var perpendicular = Vector2(-direction.y, direction.x)
		var offset = perpendicular * randf_range(-15, 15)
		points.append(point + offset)
	points.append(to)
	
	lightning.points = points
	
	var tween = create_tween()
	tween.tween_property(lightning, "modulate:a", 0.0, 0.3)
	await tween.finished
	lightning.queue_free()

func create_screen_flash(color: Color):
	var flash = ColorRect.new()
	flash.color = color
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(flash)
	
	var viewport_size = get_viewport().get_visible_rect().size
	flash.size = viewport_size
	flash.position = Vector2.ZERO
	
	var tween = create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.5)
	await tween.finished
	flash.queue_free()

func update_waypoint_markers():
	for marker in waypoint_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	waypoint_markers.clear()
	
	var souls = souls_container.get_children()
	if souls.is_empty():
		return
	
	var viewport_size = get_viewport().get_visible_rect().size
	var camera_pos = camera.global_position if camera else player.global_position
	var camera_zoom = camera.zoom if camera else Vector2.ONE
	
	var screen_half_width = (viewport_size.x / camera_zoom.x) / 2.0
	var screen_half_height = (viewport_size.y / camera_zoom.y) / 2.0
	
	for soul in souls:
		if not is_instance_valid(soul):
			continue
		
		var relative_pos = soul.global_position - camera_pos
		var is_offscreen = abs(relative_pos.x) > screen_half_width or abs(relative_pos.y) > screen_half_height
		
		if is_offscreen:
			var marker = create_waypoint_marker(soul, viewport_size, camera_pos, camera_zoom)
			if marker:
				waypoint_markers.append(marker)

func create_waypoint_marker(soul: Node2D, viewport_size: Vector2, camera_pos: Vector2, camera_zoom: Vector2) -> Node2D:
	var marker = Node2D.new()
	marker.z_index = 100
	
	var direction = (soul.global_position - camera_pos).normalized()
	ui.add_child(marker)
	
	var screen_center = viewport_size / 2.0
	var edge_margin = 30.0
	var max_x = viewport_size.x / 2.0 - edge_margin
	var max_y = viewport_size.y / 2.0 - edge_margin
	
	var t_x = max_x / abs(direction.x) if direction.x != 0 else INF
	var t_y = max_y / abs(direction.y) if direction.y != 0 else INF
	var t = min(t_x, t_y)
	
	var edge_pos = screen_center + direction * t
	marker.position = edge_pos
	var angle = direction.angle()
	
	marker.draw.connect(func():
		var arrow_size = 15.0
		var arrow_color = Color.CYAN
		
		var points = PackedVector2Array([
			Vector2(0, -arrow_size),
			Vector2(-arrow_size * 0.6, arrow_size * 0.5),
			Vector2(arrow_size * 0.6, arrow_size * 0.5)
		])
		marker.draw_colored_polygon(points, arrow_color)
		marker.draw_polyline(points + PackedVector2Array([points[0]]), Color.WHITE, 1.5, true)
	)
	
	marker.rotation = angle + PI / 2
	marker.queue_redraw()
	return marker

func win_game():
	waypoints_active = false
	
	for marker in waypoint_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	waypoint_markers.clear()
	
	calculate_final_score()
	
	ui.show_message("✨ ALL SOULS IGNITED! ✨", Color.GOLD)
	game_over = true
	player.set_physics_process(false)
	
	if audio_manager:
		audio_manager.play_victory_sound()
	
	await get_tree().create_timer(3.0).timeout
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func calculate_final_score():
	var final_score = souls_ignited * 100
	final_score += highest_combo * 500
	final_score += performance_stats.chain_reactions_triggered * 1000
	
	print("=== FINAL STATS ===")
	print("Total Time: ", total_time)
	print("Highest Combo: ", highest_combo)
	print("Chain Reactions: ", performance_stats.chain_reactions_triggered)
	print("Final Score: ", final_score)

func _on_player_dead():
	if not game_over:
		waypoints_active = false
		
		for marker in waypoint_markers:
			if is_instance_valid(marker):
				marker.queue_free()
		waypoint_markers.clear()
		
		ui.show_message("💀 Soul Faded... 💀", Color.RED)
		game_over = true
		
		if audio_manager:
			audio_manager.play_death_sound()
		
		await get_tree().create_timer(2.0).timeout
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_player_life_changed(current, maximum):
	ui.update_life(current, maximum)
	
	if audio_manager and current < maximum * 0.3:
		audio_manager.play_low_health_sound()
