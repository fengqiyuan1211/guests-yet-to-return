extends Node
## Shared button feedback, with explicit material cues for shop transactions.
var voices: Array[AudioStreamPlayer]=[]
var clips: Dictionary={}
var focused:=true
var played:=0
var last_cue:=""
var last_click:=-1.0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	for i in range(8):
		var voice:=AudioStreamPlayer.new()
		voice.bus=&"SFX"
		add_child(voice)
		voices.append(voice)
	get_tree().node_added.connect(_node_added)
	_scan(get_tree().root)

func _scan(node: Node) -> void:
	_node_added(node)
	for child in node.get_children(): _scan(child)

func _node_added(node: Node) -> void:
	if node is BaseButton and not node.pressed.is_connected(_button.bind(node)):
		node.pressed.connect(_button.bind(node))

func _button(button: BaseButton) -> void:
	if is_instance_valid(button) and not button.disabled and not button.get_meta("custom_audio",false): play("click")

func material(item: Dictionary) -> String:
	var id:=str(item.get("id",""))
	if id.contains("mint"): return "leaf"
	if id.contains("sugar"): return "grain"
	if item.get("category","")=="杯型": return "glass"
	if item.get("category","")=="器材": return "metal"
	if item.get("category","")=="装饰品": return "fruit"
	return "bottle"

func product(item: Dictionary, purchased:=false) -> void:
	play(("purchase-" if purchased else "")+material(item))

func play(cue: String) -> void:
	if not focused: return
	var now:=Time.get_ticks_msec()/1000.0
	if cue=="click" and now-last_click<.045: return
	if cue=="click": last_click=now
	if not clips.has(cue):
		var path:="res://assets/audio/interface/"+cue+".wav"
		if not ResourceLoader.exists(path): return
		clips[cue]=load(path)
	var voice: AudioStreamPlayer=voices[played%voices.size()]
	voice.stop()
	voice.stream=clips[cue]
	voice.volume_linear=.65 if cue.begins_with("purchase-") else .5
	voice.pitch_scale=randf_range(.98,1.02)
	voice.play()
	played+=1
	last_cue=cue

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused=false
		for voice in voices: voice.stop()
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN: focused=true
