extends Node
## Persistent music follows the business clock, independently of page navigation.
signal volumes_changed

const DAY_TRACKS := [
	"res://assets/audio/music/day-country-waltz.ogg",
	"res://assets/audio/music/day-richer.ogg",
]
const NIGHT_TRACK := "res://assets/audio/music/night-jazz.mp3"
const NIGHT_TRACKS := [
	NIGHT_TRACK,
	"res://assets/audio/music/night-laura-source.mp3",
]
const WORKBENCH_TRACK := "res://assets/audio/music/workbench-george-street.mp3"
const FADE_SECONDS := 3.5
const DEFAULT_VOLUMES := {"Master": 80.0, "Music": 75.0, "SFX": 80.0}

var settings_path := "user://audio_settings.cfg"
var volumes: Dictionary = DEFAULT_VOLUMES.duplicate()
var players: Array[AudioStreamPlayer] = []
var active_index := -1
var active_path := ""
var workbench_owners: Dictionary = {}
var hall_path := ""
var hall_position := 0.0
var night_mode := false
var night_index := 0
var day_index := 0
var fade: Tween
var _save_delay := -1.0
var _streams: Dictionary = {}
var _missing: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audio-settings="):
			settings_path = arg.trim_prefix("--audio-settings=")
	_ensure_bus("Music")
	_ensure_bus("SFX")
	load_settings()
	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.name = "MusicDeck%d" % i
		player.bus = &"Music"
		player.volume_linear = 0.0
		add_child(player)
		players.append(player)
	# GameSession is earlier in the autoload list, so the saved clock is ready.
	night_mode = is_night(TimeManager.minutes_since_midnight)
	_play_path(NIGHT_TRACK if night_mode else DAY_TRACKS[day_index])

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")

func is_night(minutes: int) -> bool:
	return minutes >= TimeManager.OPEN_MINUTE or minutes < TimeManager.CLOSE_MINUTE

func _process(delta: float) -> void:
	if _save_delay >= 0.0:
		_save_delay -= delta
		if _save_delay < 0.0:
			save_settings()
	var desired_night := is_night(TimeManager.minutes_since_midnight)
	if desired_night != night_mode:
		night_mode = desired_night
		if not workbench_owners.is_empty():
			hall_path="" # Resume the playlist for the new time of day when leaving.
		elif night_mode:
			night_index = 0
			_play_path(NIGHT_TRACKS[night_index])
		else:
			_play_path(DAY_TRACKS[day_index])
	if active_index < 0 or (is_instance_valid(fade) and fade.is_running()):
		return
	var current := players[active_index]
	if not current.playing or current.stream.get_length() - current.get_playback_position() <= FADE_SECONDS:
		if not workbench_owners.is_empty():
			_play_path(WORKBENCH_TRACK)
		elif night_mode:
			night_index = (night_index + 1) % NIGHT_TRACKS.size()
			_play_path(NIGHT_TRACKS[night_index])
		else:
			day_index = (day_index + 1) % DAY_TRACKS.size()
			_play_path(DAY_TRACKS[day_index])

func _stream_for(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	if _missing.has(path):
		return null
	if not ResourceLoader.exists(path):
		_missing[path] = true
		push_warning("Music asset unavailable: %s" % path)
		return null
	var stream := load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		stream.loop = false # The two decks handle the overlap without a silent gap.
	_streams[path] = stream
	return stream

func _play_path(path: String, from_position := 0.0) -> void:
	var stream := _stream_for(path)
	if stream == null:
		return
	if is_instance_valid(fade):
		fade.kill()
	# On a clock reversal during a fade, reuse the requested deck if still playing.
	var next_index := -1
	if path != active_path:
		for i in range(players.size()):
			if players[i].playing and players[i].stream == stream:
				next_index = i
	if next_index < 0:
		next_index = 0 if active_index < 0 else 1 - active_index
		players[next_index].stop()
		players[next_index].stream = stream
		players[next_index].volume_linear = 0.0
		players[next_index].pitch_scale = 0.94 if NIGHT_TRACKS.has(path) else 1.0
		players[next_index].play(from_position)
	active_index = next_index
	active_path = path
	fade = create_tween().set_parallel(true)
	fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in range(players.size()):
		fade.tween_property(players[i], "volume_linear", 1.0 if i == active_index else 0.0, FADE_SECONDS)
	var outgoing := players[1 - active_index]
	fade.chain().tween_callback(outgoing.stop)

func get_volume(bus_name: String) -> float:
	return float(volumes.get(bus_name, 100.0))

func set_volume(bus_name: String, value: float) -> void:
	if not DEFAULT_VOLUMES.has(bus_name) or not is_finite(value):
		return
	volumes[bus_name] = clampf(value, 0.0, 100.0)
	_apply_volume(bus_name)
	_save_delay = 0.35
	volumes_changed.emit()

func _apply_volume(bus_name: String) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	var value := get_volume(bus_name) / 100.0
	AudioServer.set_bus_mute(index, value <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))

func load_settings() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	for bus_name: String in DEFAULT_VOLUMES:
		var value: Variant = config.get_value("volume", bus_name, DEFAULT_VOLUMES[bus_name])
		if not (value is float or value is int) or not is_finite(float(value)):
			value = DEFAULT_VOLUMES[bus_name]
		volumes[bus_name] = clampf(float(value), 0.0, 100.0)
		_apply_volume(bus_name)

func save_settings() -> bool:
	var config := ConfigFile.new()
	for bus_name: String in DEFAULT_VOLUMES:
		config.set_value("volume", bus_name, volumes[bus_name])
	var error := config.save(settings_path + ".tmp")
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(settings_path + ".tmp"), ProjectSettings.globalize_path(settings_path))
	if error != OK:
		push_warning("Could not save audio preferences: %s" % error_string(error))
	return error == OK

func _exit_tree() -> void:
	if _save_delay >= 0.0:
		save_settings()
	if is_instance_valid(fade):
		fade.kill()
	for player in players:
		player.stop()
		player.stream = null
	_streams.clear()

func acquire_workbench(owner: Node) -> void:
	if workbench_owners.has(owner.get_instance_id()): return
	var first:=workbench_owners.is_empty()
	workbench_owners[owner.get_instance_id()]=true
	if not first: return
	hall_path=active_path
	hall_position=players[active_index].get_playback_position() if active_index>=0 else 0.0
	_play_path(WORKBENCH_TRACK)

func release_workbench(owner: Node) -> void:
	if not workbench_owners.has(owner.get_instance_id()): return
	workbench_owners.erase(owner.get_instance_id())
	if not workbench_owners.is_empty(): return
	if not is_inside_tree() or is_queued_for_deletion(): return
	var path: String=hall_path if not hall_path.is_empty() else (NIGHT_TRACKS[night_index] if night_mode else DAY_TRACKS[day_index])
	_play_path(path,hall_position if not hall_path.is_empty() else 0.0)
