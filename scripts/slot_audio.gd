extends Node
## Short locally synthesized mechanical and payout sounds; no external audio assets.
var clips: Dictionary = {}
var players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	clips["pull"] = tone(95, 0.17, 0.3)
	clips["tick"] = tone(520, 0.025, 0.08)
	clips["stop"] = tone(175, 0.12, 0.3)
	clips["coin"] = tone(1046, 0.35, 0.14)
	clips["jackpot"] = tone(659, 0.9, 0.18)
	for i in range(4):
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		players.append(player)

func tone(hz: float, seconds: float, gain: float) -> AudioStreamWAV:
	var count := int(seconds * 22050)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var time := i / 22050.0
		var envelope := exp(-time * 9) * minf(time * 600, 1)
		var sample := (sin(time * hz * TAU) + 0.35 * sin(time * hz * TAU * 1.5)) * envelope * gain
		data.encode_u16(i * 2, int(sample * 24000) & 65535)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = data
	return stream

func play_sound(key: String) -> void:
	for player in players:
		if not player.playing:
			player.stream = clips[key]
			player.play()
			return
