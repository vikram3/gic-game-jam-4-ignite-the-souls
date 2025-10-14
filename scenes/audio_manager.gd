extends Node

var music_player: AudioStreamPlayer
var sfx_players := []
var max_sfx_players := 8
var current_sfx_index := 0
var low_health_timer := 0.0
var low_health_cooldown := 2.0

func _ready():
	setup_audio_players()
	generate_music()

func setup_audio_players():
	# Music player
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	music_player.bus = "Master"
	
	# SFX players pool
	for i in range(max_sfx_players):
		var player = AudioStreamPlayer.new()
		add_child(player)
		player.bus = "Master"
		sfx_players.append(player)

func _process(delta):
	low_health_timer += delta

func generate_music():
	# Generate simple ambient music using AudioStreamGenerator
	var generator = AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = 0.1
	
	music_player.stream = generator
	music_player.volume_db = -10.0

func play_music():
	if music_player:
		music_player.play()

func pause_music():
	if music_player:
		music_player.stream_paused = true

func resume_music():
	if music_player:
		music_player.stream_paused = false

func get_next_sfx_player() -> AudioStreamPlayer:
	var player = sfx_players[current_sfx_index]
	current_sfx_index = (current_sfx_index + 1) % max_sfx_players
	return player

func play_ignite_sound():
	var player = get_next_sfx_player()
	play_synthesized_sound(player, 880.0, 0.3, 0.15)

func play_combo_sound(combo: int):
	var player = get_next_sfx_player()
	var pitch = 440.0 + (combo * 110.0)
	play_synthesized_sound(player, pitch, 0.2, 0.1)

func play_victory_sound():
	var player = get_next_sfx_player()
	play_synthesized_sound(player, 1046.5, 0.5, 0.4)

func play_death_sound():
	var player = get_next_sfx_player()
	play_synthesized_sound(player, 220.0, 0.3, 0.5)

func play_low_health_sound():
	if low_health_timer < low_health_cooldown:
		return
	low_health_timer = 0.0
	
	var player = get_next_sfx_player()
	play_synthesized_sound(player, 330.0, 0.15, 0.1)

func play_dash_sound():
	var player = get_next_sfx_player()
	play_synthesized_sound(player, 660.0, 0.2, 0.1)

func play_ui_click():
	var player = get_next_sfx_player()
	play_synthesized_sound(player, 523.25, 0.1, 0.05)

# Synthesize a simple tone
func play_synthesized_sound(player: AudioStreamPlayer, frequency: float, volume: float, duration: float):
	var playback: AudioStreamGeneratorPlayback
	var generator = AudioStreamGenerator.new()
	generator.mix_rate = 44100.0
	generator.buffer_length = 0.1
	
	player.stream = generator
	player.volume_db = linear_to_db(volume)
	player.play()
	
	playback = player.get_stream_playback()
	if not playback:
		return
	
	var phase = 0.0
	var increment = frequency / generator.mix_rate
	var frames = int(duration * generator.mix_rate)
	
	# Generate tone with envelope
	for i in range(frames):
		var envelope = 1.0
		if i < frames * 0.1:  # Attack
			envelope = float(i) / (frames * 0.1)
		elif i > frames * 0.7:  # Release
			envelope = 1.0 - (float(i - frames * 0.7) / (frames * 0.3))
		
		var sample = sin(phase * TAU) * envelope
		playback.push_frame(Vector2(sample, sample))
		phase = fmod(phase + increment, 1.0)
	
	# Stop after duration
	await get_tree().create_timer(duration).timeout
	if player.playing:
		player.stop()

func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * log(linear) / log(10.0)
