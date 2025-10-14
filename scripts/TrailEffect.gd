extends Node2D

@export var trail_length := 6
@export var trail_lifetime := 0.3
@export var spawn_interval := 0.08
@export var trail_color := Color(0.5, 0.8, 1.0, 0.5)

var trail_ghosts := []
var spawn_timer := 0.0
var parent_sprite: Sprite2D
var is_player_dashing := false

func _ready():
	var parent = get_parent()
	parent_sprite = parent.get_node_or_null("Icon")
	
	if not parent_sprite:
		push_warning("No Icon sprite found on parent")
		return
	
	if parent.has_signal("started_dash"):
		parent.started_dash.connect(_on_dash_started)
	if parent.has_signal("stopped_dash"):
		parent.stopped_dash.connect(_on_dash_stopped)

func _process(delta):
	if not parent_sprite:
		return
	
	spawn_timer += delta
	
	var parent = get_parent()
	var is_moving = false
	if parent is CharacterBody2D:
		is_moving = parent.velocity.length() > 30
	
	if spawn_timer >= spawn_interval and (is_moving or is_player_dashing):
		spawn_timer = 0.0
		create_trail_ghost()
	
	update_trail_ghosts(delta)

func create_trail_ghost():
	if trail_ghosts.size() >= trail_length:
		var oldest = trail_ghosts.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	
	var ghost = Sprite2D.new()
	ghost.texture = parent_sprite.texture
	ghost.hframes = parent_sprite.hframes
	ghost.vframes = parent_sprite.vframes
	ghost.frame = parent_sprite.frame
	
	ghost.global_position = get_parent().global_position
	ghost.global_rotation = parent_sprite.global_rotation
	ghost.scale = parent_sprite.scale * get_parent().scale
	ghost.modulate = trail_color
	ghost.z_index = get_parent().z_index - 1
	
	ghost.set_meta("lifetime", trail_lifetime)
	ghost.set_meta("max_lifetime", trail_lifetime)
	
	get_tree().root.add_child(ghost)
	trail_ghosts.append(ghost)

func update_trail_ghosts(delta):
	for ghost in trail_ghosts:
		if not is_instance_valid(ghost):
			trail_ghosts.erase(ghost)
			continue
		
		var lifetime = ghost.get_meta("lifetime")
		lifetime -= delta
		ghost.set_meta("lifetime", lifetime)
		
		if lifetime <= 0:
			ghost.queue_free()
			trail_ghosts.erase(ghost)
		else:
			var max_lifetime = ghost.get_meta("max_lifetime")
			var alpha = (lifetime / max_lifetime) * trail_color.a
			ghost.modulate.a = alpha
			
			var scale_factor = 0.7 + (lifetime / max_lifetime) * 0.3
			ghost.scale = parent_sprite.scale * get_parent().scale * scale_factor

func _on_dash_started():
	is_player_dashing = true
	trail_color.a = 0.7
	spawn_interval = 0.04

func _on_dash_stopped():
	is_player_dashing = false
	trail_color.a = 0.5
	spawn_interval = 0.08

func _exit_tree():
	for ghost in trail_ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	trail_ghosts.clear()
