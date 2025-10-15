extends Node

@onready var player = $"../player_soul"
@onready var souls_container = $"../Souls"
@onready var ui = $"../UI"
@onready var camera = $"../Camera2D"
@onready var audio_manager = $AudioManager

# Core Settings
@export_group("Soul Spawning")
@export var total_souls := 100
@export var spawn_area_margin := 30.0
@export var min_soul_distance := 40.0
@export var world_bounds := Rect2(-200, -150, 800, 500)
@export var near_player_souls := 3
@export var near_player_radius := 80.0
@export var spawn_retry_attempts := 300
@export var adaptive_spacing := true

@export_group("Chain Reactions")
@export var chain_reaction_bonus := 2.0
@export var chain_ignition_threshold := 20
@export var chain_ignition_range := 120.0
@export var chain_reaction_life_bonus := 0.5

@export_group("Waypoints")
@export var waypoint_threshold := 15
@export var waypoint_pulse_speed := 2.0

@export_group("Advanced Features")
@export var dynamic_difficulty := true
@export var time_slow_on_combo := true
@export var screen_shake_on_combo := true
@export var adaptive_world_bounds := true

# Game State
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

# Advanced Tracking
var highest_combo := 0
var total_time := 0.0
var score_multiplier := 1.0
var power_up_active := false
var power_up_timer := 0.0
var active_power_ups := {}
var spawn_grid := {}
var grid_cell_size := 50.0

var performance_stats := {
	"ignites_per_second": 0.0,
	"average_combo": 0.0,
	"chain_reactions_triggered": 0,
	"total_combos": 0,
	"power_ups_activated": 0,
	"perfect_chains": 0
}

# Spawn optimization
var spatial_hash := {}
var failed_spawn_attempts := 0

func _ready():
	initialize_game()

func initialize_game():
	setup_camera()
	initialize_spatial_grid()
	
	var spawn_success = spawn_souls_optimized(total_souls)
	
	if not spawn_success:
		push_warning("Failed to spawn all souls. Adjusting parameters...")
		adjust_spawn_parameters()
		spawn_souls_optimized(total_souls - souls_container.get_child_count())
	
	ui.update_score(souls_ignited, total_souls)
	ui.update_combo(0)
	ui.show_pause_menu(false)
	
	connect_signals()
	
	if audio_manager:
		audio_manager.play_music()
	
	print("Game initialized: ", souls_container.get_child_count(), "/", total_souls, " souls spawned")

func connect_signals():
	player.soul_ignited.connect(_on_player_ignite)
	player.soul_extinguished.connect(_on_player_dead)
	player.life_changed.connect(_on_player_life_changed)

func setup_camera():
	if camera:
		camera.position = player.position
		camera.enabled = true
		camera.zoom = Vector2(3.5, 3.5)

func initialize_spatial_grid():
	spatial_hash.clear()
	grid_cell_size = min_soul_distance * 2.0

func get_grid_cell(pos: Vector2) -> Vector2i:
	return Vector2i(
		int(pos.x / grid_cell_size),
		int(pos.y / grid_cell_size)
	)

func add_to_spatial_hash(pos: Vector2):
	var cell = get_grid_cell(pos)
	if not spatial_hash.has(cell):
		spatial_hash[cell] = []
	spatial_hash[cell].append(pos)

func get_nearby_positions(pos: Vector2, radius: float) -> Array:
	var nearby = []
	var cell = get_grid_cell(pos)
	var cell_radius = int(ceil(radius / grid_cell_size))
	
	for x in range(cell.x - cell_radius, cell.x + cell_radius + 1):
		for y in range(cell.y - cell_radius, cell.y + cell_radius + 1):
			var check_cell = Vector2i(x, y)
			if spatial_hash.has(check_cell):
				nearby.append_array(spatial_hash[check_cell])
	
	return nearby

func adjust_spawn_parameters():
	# Dynamically adjust parameters if spawning fails
	if adaptive_spacing:
		min_soul_distance *= 0.9
		print("Adjusted min_soul_distance to: ", min_soul_distance)
	
	if adaptive_world_bounds:
		world_bounds = world_bounds.grow(50)
		print("Expanded world_bounds to: ", world_bounds)

func spawn_souls_optimized(amount: int) -> bool:
	var scene = preload("res://scenes/soul.tscn")
	var souls_spawned = 0
	var total_attempts = 0
	var max_total_attempts = amount * 10
	
	# Phase 1: Spawn near player
	var near_spawn_count = min(near_player_souls, amount)
	for i in range(near_spawn_count):
		var soul_pos = find_valid_spawn_position_optimized(true)
		if soul_pos != Vector2.ZERO:
			create_soul(scene, soul_pos)
			souls_spawned += 1
		total_attempts += 1
		
		if total_attempts > max_total_attempts:
			break
	
	# Phase 2: Use Poisson Disk Sampling for better distribution
	var remaining = amount - souls_spawned
	if remaining > 0:
		var poisson_positions = generate_poisson_disk_samples(remaining, min_soul_distance)
		
		for pos in poisson_positions:
			if souls_spawned >= amount:
				break
			
			if is_valid_spawn_location(pos, false):
				create_soul(scene, pos)
				spawn_positions.append(pos)
				add_to_spatial_hash(pos)
				souls_spawned += 1
	
	# Phase 3: Fill remaining with relaxed constraints
	if souls_spawned < amount:
		var relaxed_distance = min_soul_distance * 0.7
		
		for i in range(amount - souls_spawned):
			var soul_pos = find_valid_spawn_position_relaxed(relaxed_distance)
			if soul_pos != Vector2.ZERO:
				create_soul(scene, soul_pos)
				souls_spawned += 1
			
			total_attempts += 1
			if total_attempts > max_total_attempts:
				break
	
	var success = souls_spawned >= amount * 0.95
	if not success:
		push_warning("Only spawned ", souls_spawned, "/", amount, " souls")
	
	return success

func generate_poisson_disk_samples(target_count: int, min_dist: float) -> Array[Vector2]:
	var samples: Array[Vector2] = []
	var active_list: Array[Vector2] = []
	var k = 30 # Attempts per sample
	
	# Start with a random point avoiding player
	var first_point = Vector2(
		randf_range(world_bounds.position.x, world_bounds.position.x + world_bounds.size.x),
		randf_range(world_bounds.position.y, world_bounds.position.y + world_bounds.size.y)
	)
	
	if first_point.distance_to(player.position) > spawn_area_margin:
		samples.append(first_point)
		active_list.append(first_point)
		add_to_spatial_hash(first_point)
	
	while active_list.size() > 0 and samples.size() < target_count:
		var idx = randi() % active_list.size()
		var point = active_list[idx]
		var found = false
		
		for _i in range(k):
			var angle = randf() * TAU
			var distance = randf_range(min_dist, min_dist * 2.0)
			var new_point = point + Vector2(cos(angle), sin(angle)) * distance
			
			if not world_bounds.has_point(new_point):
				continue
			
			if new_point.distance_to(player.position) < spawn_area_margin:
				continue
			
			var nearby = get_nearby_positions(new_point, min_dist)
			var valid = true
			
			for nearby_pos in nearby:
				if new_point.distance_to(nearby_pos) < min_dist:
					valid = false
					break
			
			if valid:
				samples.append(new_point)
				active_list.append(new_point)
				add_to_spatial_hash(new_point)
				found = true
				break
		
		if not found:
			active_list.remove_at(idx)
	
	return samples

func find_valid_spawn_position_optimized(near_player: bool) -> Vector2:
	var attempts = 0
	
	while attempts < spawn_retry_attempts:
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
		
		if is_valid_spawn_location(soul_pos, near_player):
			spawn_positions.append(soul_pos)
			add_to_spatial_hash(soul_pos)
			return soul_pos
		
		attempts += 1
	
	failed_spawn_attempts += 1
	return Vector2.ZERO

func find_valid_spawn_position_relaxed(relaxed_distance: float) -> Vector2:
	for attempt in range(spawn_retry_attempts):
		var soul_pos = Vector2(
			randf_range(world_bounds.position.x, world_bounds.position.x + world_bounds.size.x),
			randf_range(world_bounds.position.y, world_bounds.position.y + world_bounds.size.y)
		)
		
		if not world_bounds.has_point(soul_pos):
			continue
		
		if soul_pos.distance_to(player.position) < spawn_area_margin * 0.5:
			continue
		
		var nearby = get_nearby_positions(soul_pos, relaxed_distance)
		var valid = true
		
		for pos in nearby:
			if soul_pos.distance_to(pos) < relaxed_distance:
				valid = false
				break
		
		if valid:
			spawn_positions.append(soul_pos)
			add_to_spatial_hash(soul_pos)
			return soul_pos
	
	return Vector2.ZERO

func is_valid_spawn_location(pos: Vector2, near_player: bool) -> bool:
	if not world_bounds.has_point(pos):
		return false
	
	if not near_player and pos.distance_to(player.position) < spawn_area_margin:
		return false
	
	var nearby = get_nearby_positions(pos, min_soul_distance)
	for nearby_pos in nearby:
		if pos.distance_to(nearby_pos) < min_soul_distance:
			return false
	
	return true

func create_soul(scene: PackedScene, pos: Vector2):
	var soul = scene.instantiate()
	soul.position = pos
	soul.set_difficulty(difficulty_multiplier)
	souls_container.add_child(soul)

func _process(delta):
	total_time += delta
	
	if Input.is_action_just_pressed("ui_cancel") and not game_over:
		toggle_pause()
	
	if camera and player and not game_paused:
		camera.position = lerp(camera.position, player.position, 0.1)
	
	if waypoints_active:
		update_waypoint_markers()
	
	update_active_power_ups(delta)
	
	if dynamic_difficulty and total_time > 10.0:
		adjust_dynamic_difficulty()
	
	update_performance_stats()

func update_active_power_ups(delta):
	var expired_power_ups = []
	
	for power_up_type in active_power_ups:
		active_power_ups[power_up_type] -= delta
		
		if active_power_ups[power_up_type] <= 0:
			expired_power_ups.append(power_up_type)
	
	for power_up_type in expired_power_ups:
		deactivate_power_up(power_up_type)
		active_power_ups.erase(power_up_type)

func update_performance_stats():
	if total_time > 0:
		performance_stats.ignites_per_second = souls_ignited / total_time
	
	if performance_stats.total_combos > 0:
		performance_stats.average_combo = float(souls_ignited) / performance_stats.total_combos

func toggle_pause():
	game_paused = !game_paused
	get_tree().paused = game_paused
	ui.show_pause_menu(game_paused)
	
	if audio_manager:
		if game_paused:
			audio_manager.pause_music()
		else:
			audio_manager.resume_music()

func _on_player_ignite():
	souls_ignited += 1
	souls_since_last_chain += 1
	
	if audio_manager:
		audio_manager.play_ignite_sound()
	
	if ui.has_method("show_ignite_popup"):
		ui.show_ignite_popup(player.global_position)
	
	process_combo_system()
	ui.update_score(souls_ignited, total_souls)
	ui.update_combo(combo_count)
	
	difficulty_multiplier += 0.05
	player.increase_difficulty(difficulty_multiplier)
	
	check_chain_reaction()
	check_waypoint_activation()
	check_win_condition()

func process_combo_system():
	var current_time = Time.get_ticks_msec() / 1000.0
	var combo_window = 3.0
	
	if current_time - last_ignite_time < combo_window:
		combo_count += 1
		performance_stats.total_combos += 1
		
		if combo_count > highest_combo:
			highest_combo = combo_count
		
		ui.show_combo_effect(combo_count)
		if audio_manager:
			audio_manager.play_combo_sound(combo_count)
		
		if time_slow_on_combo and combo_count >= 5:
			apply_time_slow(0.7, 0.5)
		
		if screen_shake_on_combo and camera and camera.has_method("shake"):
			var shake_intensity = min(2.0 + combo_count * 0.5, 10.0)
			camera.shake(shake_intensity, 0.2)
		
		score_multiplier = 1.0 + (combo_count * 0.1)
		
		# Milestone rewards
		match combo_count:
			5:
				activate_power_up("speed_boost", 5.0)
			10:
				activate_power_up("life_regen", 8.0)
			15:
				activate_power_up("invincibility", 3.0)
			20:
				activate_power_up("double_points", 10.0)
	else:
		combo_count = 1
		score_multiplier = 1.0
		performance_stats.total_combos += 1
	
	last_ignite_time = current_time

func check_chain_reaction():
	if souls_since_last_chain >= chain_ignition_threshold:
		trigger_chain_reaction(player.global_position)
		souls_since_last_chain = 0

func check_waypoint_activation():
	var remaining_souls = total_souls - souls_ignited
	if remaining_souls <= waypoint_threshold and not waypoints_active:
		activate_waypoints()

func check_win_condition():
	if souls_ignited >= total_souls:
		win_game()

func apply_time_slow(scale: float, duration: float):
	Engine.time_scale = scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

func activate_power_up(type: String, duration: float):
	active_power_ups[type] = duration
	performance_stats.power_ups_activated += 1
	
	match type:
		"speed_boost":
			player.move_speed *= 1.5
			show_power_up_message("⚡ SPEED BOOST! ⚡", Color.CYAN)
		
		"invincibility":
			player.life_loss_rate = 0.0
			show_power_up_message("🛡️ INVINCIBLE! 🛡️", Color.GOLD)
		
		"life_regen":
			start_life_regeneration(duration)
			show_power_up_message("💚 LIFE REGENERATION! 💚", Color.GREEN)
		
		"double_points":
			score_multiplier *= 2.0
			show_power_up_message("✨ DOUBLE POINTS! ✨", Color.YELLOW)

func show_power_up_message(message: String, color: Color):
	if ui.has_method("show_message"):
		ui.show_message(message, color)

func start_life_regeneration(duration: float):
	var regen_rate = 5.0
	var elapsed = 0.0
	
	while elapsed < duration:
		await get_tree().create_timer(0.5).timeout
		elapsed += 0.5
		
		if player.has_method("add_bonus_life"):
			player.add_bonus_life(regen_rate * 0.5)

func deactivate_power_up(type: String):
	match type:
		"speed_boost":
			player.move_speed = 80.0
		
		"invincibility":
			player.life_loss_rate = 1.0
		
		"double_points":
			score_multiplier = 1.0 + (combo_count * 0.1)

func adjust_dynamic_difficulty():
	var performance = souls_ignited / total_time
	var target_performance = 1.0
	
	if performance > target_performance * 1.5:
		difficulty_multiplier = min(difficulty_multiplier + 0.01, 3.0)
	elif performance < target_performance * 0.5:
		difficulty_multiplier = max(difficulty_multiplier - 0.01, 0.5)

func activate_waypoints():
	waypoints_active = true
	print("🎯 Waypoints activated! ", total_souls - souls_ignited, " souls remaining")
	
	if ui.has_method("show_message"):
		ui.show_message("🎯 WAYPOINTS ACTIVATED", Color.CYAN)
		await get_tree().create_timer(2.0).timeout
		ui.show_message("", Color.WHITE)

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
		
		if chain_reaction_souls.size() >= 10:
			performance_stats.perfect_chains += 1
		
		print("🔥 CHAIN REACTION! ", chain_reaction_souls.size(), " souls affected")
		
		if ui and ui.has_method("show_message"):
			ui.show_message("🔥 CHAIN REACTION x%d! 🔥" % chain_reaction_souls.size(), Color.ORANGE_RED)
		
		create_screen_flash(Color(1.0, 0.5, 0.0, 0.3))
		if camera and camera.has_method("shake"):
			camera.shake(min(8.0 + chain_reaction_souls.size() * 0.5, 15.0), 0.5)
		
		start_chain_sequence()
		
		await get_tree().create_timer(1.5).timeout
		if ui and ui.has_method("show_message"):
			ui.show_message("", Color.WHITE)

func start_chain_sequence():
	create_chain_explosion_ring(player.global_position)
	
	var chain_delay = 0.08 if chain_reaction_souls.size() < 20 else 0.04
	
	for i in range(chain_reaction_souls.size()):
		var soul = chain_reaction_souls[i]
		if is_instance_valid(soul):
			await get_tree().create_timer(chain_delay).timeout
			ignite_soul_by_chain(soul)

func ignite_soul_by_chain(soul):
	if not is_instance_valid(soul):
		return
	
	souls_ignited += 1
	combo_count += 1
	
	create_chain_lightning(player.global_position, soul.global_position)
	
	if player.has_method("add_bonus_life"):
		player.add_bonus_life(chain_reaction_life_bonus)
	
	ui.update_score(souls_ignited, total_souls)
	ui.update_combo(combo_count)
	
	if audio_manager:
		audio_manager.play_combo_sound(min(combo_count, 10))
	
	if soul.has_method("start_burn_effect"):
		soul.start_burn_effect()
	else:
		soul.queue_free()

func create_chain_explosion_ring(origin: Vector2):
	var ring = Node2D.new()
	get_tree().root.add_child(ring)
	ring.global_position = origin
	ring.z_index = 50
	
	var ring_data = {"radius": 0.0, "alpha": 0.8, "thickness": 4.0}
	
	ring.draw.connect(func():
		ring.draw_arc(Vector2.ZERO, ring_data.radius, 0, TAU, 64, 
			Color(1.0, 0.6, 0.0, ring_data.alpha), ring_data.thickness)
		
		if ring_data.radius > chain_ignition_range * 0.5:
			ring.draw_arc(Vector2.ZERO, ring_data.radius * 0.7, 0, TAU, 48, 
				Color(1.0, 0.8, 0.2, ring_data.alpha * 0.5), ring_data.thickness * 0.5)
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
	lightning.width = 3.0
	lightning.default_color = Color(1.0, 0.8, 0.2, 0.9)
	lightning.antialiased = true
	
	var points = PackedVector2Array()
	var segments = 10
	var direction = (to - from)
	var distance = direction.length()
	direction = direction.normalized()
	
	points.append(from)
	for i in range(1, segments):
		var t = float(i) / segments
		var point = from + direction * distance * t
		var perpendicular = Vector2(-direction.y, direction.x)
		var offset = perpendicular * randf_range(-20, 20) * (1.0 - abs(t - 0.5) * 2.0)
		points.append(point + offset)
	points.append(to)
	
	lightning.points = points
	
	var tween = create_tween()
	tween.tween_property(lightning, "modulate:a", 0.0, 0.4)
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
	
	var pulse_value = (sin(Time.get_ticks_msec() / 1000.0 * waypoint_pulse_speed * TAU) + 1.0) / 2.0
	var distance_to_soul = soul.global_position.distance_to(camera_pos)
	var max_distance = sqrt(world_bounds.size.x * world_bounds.size.x + world_bounds.size.y * world_bounds.size.y)
	var distance_factor = 1.0 - clamp(distance_to_soul / max_distance, 0.0, 1.0)
	
	marker.draw.connect(func():
		var arrow_size = 12.0 + pulse_value * 6.0
		var arrow_color = Color.CYAN.lerp(Color.WHITE, pulse_value * 0.5)
		
		# Draw glow effect
		for i in range(3):
			var glow_size = arrow_size + (3 - i) * 3.0
			var glow_alpha = 0.15 * pulse_value
			var glow_points = PackedVector2Array([
				Vector2(0, -glow_size),
				Vector2(-glow_size * 0.6, glow_size * 0.5),
				Vector2(glow_size * 0.6, glow_size * 0.5)
			])
			marker.draw_colored_polygon(glow_points, Color(arrow_color.r, arrow_color.g, arrow_color.b, glow_alpha))
		
		# Draw main arrow
		var points = PackedVector2Array([
			Vector2(0, -arrow_size),
			Vector2(-arrow_size * 0.6, arrow_size * 0.5),
			Vector2(arrow_size * 0.6, arrow_size * 0.5)
		])
		marker.draw_colored_polygon(points, arrow_color)
		marker.draw_polyline(points + PackedVector2Array([points[0]]), Color.WHITE, 2.0, true)
		
		# Draw distance indicator
		var text_offset = Vector2(0, arrow_size + 15)
		var distance_text = "%dm" % int(distance_to_soul / 10)
		# Note: Cannot draw text without font, but the marker shows direction
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
	
	var final_score = calculate_final_score()
	
	if ui.has_method("show_victory_screen"):
		ui.show_victory_screen(final_score, performance_stats)
	else:
		ui.show_message("✨ 100 SOULS IGNITED! ✨\nScore: %d" % final_score, Color.GOLD)
	
	game_over = true
	player.set_physics_process(false)
	
	if audio_manager:
		audio_manager.play_victory_sound()
	
	create_victory_effects()
	
	await get_tree().create_timer(4.0).timeout
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func create_victory_effects():
	# Create celebration particle effects
	for i in range(20):
		await get_tree().create_timer(0.1).timeout
		create_celebration_burst(
			player.global_position + Vector2(randf_range(-50, 50), randf_range(-50, 50))
		)

func create_celebration_burst(pos: Vector2):
	var burst = Node2D.new()
	get_tree().root.add_child(burst)
	burst.global_position = pos
	burst.z_index = 100
	
	var particles_data = []
	for i in range(12):
		var angle = (TAU / 12.0) * i
		var velocity = Vector2(cos(angle), sin(angle)) * randf_range(50, 100)
		var color = Color.from_hsv(randf(), 0.8, 1.0)
		particles_data.append({"pos": Vector2.ZERO, "vel": velocity, "color": color, "life": 1.0})
	
	burst.draw.connect(func():
		for p in particles_data:
			if p.life > 0:
				var size = 3.0 * p.life
				burst.draw_circle(p.pos, size, Color(p.color.r, p.color.g, p.color.b, p.life))
	)
	
	var elapsed = 0.0
	while elapsed < 1.0:
		await get_tree().create_timer(0.016).timeout
		elapsed += 0.016
		
		for p in particles_data:
			p.pos += p.vel * 0.016
			p.vel.y += 200.0 * 0.016  # Gravity
			p.life -= 0.016
		
		burst.queue_redraw()
	
	burst.queue_free()

func calculate_final_score() -> int:
	var base_score = souls_ignited * 100
	var combo_bonus = highest_combo * 500
	var chain_bonus = performance_stats.chain_reactions_triggered * 1000
	var perfect_chain_bonus = performance_stats.perfect_chains * 2000
	var time_bonus = max(0, int((300.0 - total_time) * 10))
	
	var final_score = base_score + combo_bonus + chain_bonus + perfect_chain_bonus + time_bonus
	
	print("\n=== FINAL STATS ===")
	print("Total Time: %.2f seconds" % total_time)
	print("Souls Ignited: %d/%d" % [souls_ignited, total_souls])
	print("Highest Combo: %d" % highest_combo)
	print("Chain Reactions: %d" % performance_stats.chain_reactions_triggered)
	print("Perfect Chains: %d" % performance_stats.perfect_chains)
	print("Power-ups Activated: %d" % performance_stats.power_ups_activated)
	print("Average Combo: %.2f" % performance_stats.average_combo)
	print("Ignites/Second: %.2f" % performance_stats.ignites_per_second)
	print("\n--- Score Breakdown ---")
	print("Base Score: %d" % base_score)
	print("Combo Bonus: %d" % combo_bonus)
	print("Chain Bonus: %d" % chain_bonus)
	print("Perfect Chain Bonus: %d" % perfect_chain_bonus)
	print("Time Bonus: %d" % time_bonus)
	print("FINAL SCORE: %d" % final_score)
	print("==================\n")
	
	return final_score

func _on_player_dead():
	if not game_over:
		waypoints_active = false
		
		for marker in waypoint_markers:
			if is_instance_valid(marker):
				marker.queue_free()
		waypoint_markers.clear()
		
		var final_score = calculate_final_score()
		
		if ui.has_method("show_game_over_screen"):
			ui.show_game_over_screen(final_score, souls_ignited, total_souls, performance_stats)
		else:
			ui.show_message("💀 Soul Faded... 💀\nScore: %d" % final_score, Color.RED)
		
		game_over = true
		
		if audio_manager:
			audio_manager.play_death_sound()
		
		await get_tree().create_timer(3.0).timeout
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_player_life_changed(current, maximum):
	ui.update_life(current, maximum)
	
	var life_percentage = current / maximum
	
	if audio_manager and life_percentage < 0.3 and life_percentage > 0:
		audio_manager.play_low_health_sound()
	
	# Visual feedback for low health
	if life_percentage < 0.2 and camera and camera.has_method("add_chromatic_aberration"):
		camera.add_chromatic_aberration(0.5)

# Debug and utility functions
func get_game_stats() -> Dictionary:
	return {
		"souls_ignited": souls_ignited,
		"total_souls": total_souls,
		"highest_combo": highest_combo,
		"total_time": total_time,
		"difficulty": difficulty_multiplier,
		"performance": performance_stats.duplicate()
	}

func force_spawn_remaining_souls():
	var current_count = souls_container.get_child_count()
	var remaining = total_souls - current_count
	
	if remaining > 0:
		print("Force spawning ", remaining, " remaining souls...")
		min_soul_distance *= 0.5
		spawn_souls_optimized(remaining)

func reset_game_state():
	souls_ignited = 0
	combo_count = 0
	highest_combo = 0
	total_time = 0.0
	difficulty_multiplier = 1.0
	game_over = false
	waypoints_active = false
	spawn_positions.clear()
	spatial_hash.clear()
	active_power_ups.clear()
	
	performance_stats = {
		"ignites_per_second": 0.0,
		"average_combo": 0.0,
		"chain_reactions_triggered": 0,
		"total_combos": 0,
		"power_ups_activated": 0,
		"perfect_chains": 0
	}

# Input handling for debug
func _input(event):
	if OS.is_debug_build():
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_F1:
					print_debug_info()
				KEY_F2:
					force_spawn_remaining_souls()
				KEY_F3:
					trigger_chain_reaction(player.global_position)
				KEY_F4:
					activate_power_up("invincibility", 10.0)

func print_debug_info():
	print("\n=== DEBUG INFO ===")
	print("Souls spawned: ", souls_container.get_child_count())
	print("Souls ignited: ", souls_ignited)
	print("Spawn positions: ", spawn_positions.size())
	print("Failed spawn attempts: ", failed_spawn_attempts)
	print("Spatial hash cells: ", spatial_hash.size())
	print("Active power-ups: ", active_power_ups)
	print("Combo: ", combo_count)
	print("Difficulty: ", difficulty_multiplier)
	print("==================\n")
