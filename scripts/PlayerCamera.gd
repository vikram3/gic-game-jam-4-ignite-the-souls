extends Camera2D

@export var follow_target: NodePath
@export var smoothing_enabled := true
@export var smoothing_speed := 5.0
@export var look_ahead_distance := 20.0

@export var max_zoom := Vector2(4.5, 4.5)
@export var min_zoom := Vector2(3.0, 3.0)
@export var zoom_smoothing := 3.0

var target: Node2D
var shake_amount := 0.0
var shake_duration := 0.0
var original_offset := Vector2.ZERO
var target_zoom := Vector2.ONE

func _ready():
	if follow_target:
		target = get_node(follow_target)
	original_offset = offset
	enabled = true
	zoom = max_zoom
	target_zoom = max_zoom

func _process(delta):
	if not target:
		return
	
	var target_pos = target.global_position
	
	if target is CharacterBody2D:
		var velocity_dir = target.velocity.normalized()
		target_pos += velocity_dir * look_ahead_distance
	
	if smoothing_enabled:
		global_position = lerp(global_position, target_pos, smoothing_speed * delta)
	else:
		global_position = target_pos
	
	update_zoom_based_on_health(delta)
	
	if shake_duration > 0:
		shake_duration -= delta
		offset = original_offset + Vector2(
			randf_range(-shake_amount, shake_amount),
			randf_range(-shake_amount, shake_amount)
		)
	else:
		offset = lerp(offset, original_offset, 10 * delta)

func update_zoom_based_on_health(delta):
	if not target:
		return
	
	var health_percent = 1.0
	if target.has_method("get_life_percent"):
		health_percent = target.get_life_percent()
	
	target_zoom = lerp(min_zoom, max_zoom, health_percent)
	zoom = lerp(zoom, target_zoom, zoom_smoothing * delta)
	
	if health_percent < 0.3:
		var pulse = (sin(Time.get_ticks_msec() * 0.005) + 1.0) * 0.5
		var pulse_amount = 0.1 * (1.0 - health_percent)
		zoom += Vector2(pulse_amount * pulse, pulse_amount * pulse)

func shake(amount: float, duration: float):
	shake_amount = amount
	shake_duration = duration

func pulse_zoom(zoom_target: float, duration: float):
	var tween = create_tween()
	tween.tween_property(self, "zoom", Vector2(zoom_target, zoom_target), duration * 0.5)
	tween.tween_property(self, "zoom", target_zoom, duration * 0.5)

func set_zoom_limits(min_z: Vector2, max_z: Vector2):
	min_zoom = min_z
	max_zoom = max_z
