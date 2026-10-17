extends Node
## Narrative cues belong to the current line, never to the read-only backlog.
const CUES={
	"mail":["res://assets/audio/opening/mail-arrival.wav",-7.0],
	"chuckle":["res://assets/audio/opening/chuckle.wav",-12.0],
	"clink":["res://assets/audio/workbench/clink.wav",-9.0],
	"paper":["res://assets/audio/interface/foley/leaf-1.wav",-17.0],
}
var voice: AudioStreamPlayer
var ambience: AudioStreamPlayer
var last_node:=""
var last_cue:=""
var cue_count:=0
var sea_active:=false
var sea_fade: Tween

func _ready() -> void:
	voice=AudioStreamPlayer.new()
	voice.bus=&"SFX"
	add_child(voice)
	ambience=AudioStreamPlayer.new()
	ambience.bus=&"SFX"
	ambience.volume_db=-32
	ambience.stream=load("res://assets/audio/opening/shore.wav").duplicate()
	if ambience.stream is AudioStreamWAV: ambience.stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
	add_child(ambience)

func present(node: Dictionary, owner: Node) -> void:
	SaloonAudio.set_scene_context(owner,str(node.get("music","opening_home")))
	var sea: bool=node.get("background","") in ["harbor-sunset","porch"]
	if sea!=sea_active:
		sea_active=sea
		if is_instance_valid(sea_fade): sea_fade.kill()
		sea_fade=create_tween()
		if sea:
			if not ambience.playing: ambience.play()
			sea_fade.tween_property(ambience,"volume_db",-27.0,1.5)
		else:
			sea_fade.tween_property(ambience,"volume_db",-60.0,1.0)
			sea_fade.tween_callback(ambience.stop)
	var id:=str(node.get("id","ending"))
	if id==last_node: return
	last_node=id
	voice.stop()
	last_cue=str(node.get("sfx",""))
	if not CUES.has(last_cue): return
	voice.stream=load(CUES[last_cue][0])
	voice.volume_db=CUES[last_cue][1]
	voice.play()
	cue_count+=1

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_instance_valid(voice): voice.stop()
		if is_instance_valid(ambience): ambience.stream_paused=true
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN and is_instance_valid(ambience):
		ambience.stream_paused=false
