extends Node
## Local foley only. Global volume/muting stays with SaloonAudio's existing SFX bus.
const PATH := "res://assets/audio/workbench/"
var loops: Dictionary = {}
var taps: Array[AudioStreamPlayer] = []
var presses: Array[AudioStreamPlayer]=[]
var press_clock:=-1.0
var press_count:=0
var focused := true
var tap_clock := -1.0
var trigger_count := 0

func _ready() -> void:
	for id in ["pour","stir","shake"]:
		var player:=AudioStreamPlayer.new()
		player.bus=&"SFX"
		var stream:=load(PATH+id+".wav").duplicate() as AudioStreamWAV
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin=0
		stream.loop_end=roundi(stream.get_length()*stream.mix_rate)
		player.stream=stream
		player.volume_linear=0
		add_child(player)
		loops[id]=player
	for i in range(3):
		var player:=AudioStreamPlayer.new()
		player.bus=&"SFX"
		player.stream=load(PATH+"clink.wav")
		player.volume_linear=.48
		add_child(player)
		taps.append(player)

	for i in range(3):
		var player:=AudioStreamPlayer.new()
		player.bus=&"SFX"
		player.stream=load(PATH+"muddle.wav")
		add_child(player)
		presses.append(player)

func muddle(pressure: float) -> void:
	var now:=Time.get_ticks_msec()/1000.0
	if not focused or now-press_clock<.12: return
	press_clock=now
	for player in presses:
		if player.playing: continue
		player.pitch_scale=randf_range(.93,1.06)
		player.volume_linear=lerpf(.35,.65,pressure)
		player.play()
		press_count+=1
		trigger_count+=1
		return

func stop_muddle() -> void:
	for player in presses: player.stop()

func drive(delta: float, pouring: bool, motion: String, energy: float) -> void:
	for id in loops:
		var player: AudioStreamPlayer=loops[id]
		var active: bool=focused and (pouring if id=="pour" else id==motion and energy>.02)
		var target: float=(.78 if id=="pour" else lerpf(.45,.8,energy)) if active else 0.0
		if active and not player.playing:
			player.play()
			trigger_count+=1
		player.volume_linear=move_toward(player.volume_linear,target,delta*10)
		if not active and player.volume_linear<.001: player.stop()

func tap() -> void:
	var now:=Time.get_ticks_msec()/1000.0
	if not focused or now-tap_clock<.10: return
	tap_clock=now
	for player in taps:
		if not player.playing:
			player.pitch_scale=randf_range(.96,1.04)
			player.play()
			trigger_count+=1
			return

func silence() -> void:
	for player in loops.values():
		player.stop()
		player.volume_linear=0
	for player in taps: player.stop()
	stop_muddle()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused=false
		silence()
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN: focused=true

func _exit_tree() -> void:
	silence()
