extends Node
## Shared button feedback, with explicit material cues for shop transactions.
var voices: Array[AudioStreamPlayer]=[]
var clips: Dictionary={}
var focused:=true
var played:=0
var last_cue:=""
var last_click:=-1.0
var cue_times: Dictionary={}
var variants: Dictionary={}
var last_clip:=""
var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/audio/item_foley.json"))

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
	if not is_instance_valid(button) or button.disabled: return
	if button.has_meta("audio_item"):
		item(str(button.get_meta("audio_item")))
	elif not button.get_meta("custom_audio",false): play("click")

func canonical(id: String) -> String:
	return str(config.aliases.get(id,id))

func material(entry: Dictionary) -> String:
	var id:=canonical(str(entry.get("id","")))
	return str(config.items.get(id,config.fallback_by_category.get(str(entry.get("category","")),"click")))

func item(id: String) -> void:
	product({"id":id})

func product(entry: Dictionary, purchased:=false) -> void:
	var family:=material(entry)
	play(("purchase-" if purchased else "")+family,float(config.item_pitch.get(canonical(str(entry.get("id",""))),1)))

func play(cue: String, pitch:=1.0) -> void:
	if not focused: return
	var now:=Time.get_ticks_msec()/1000.0
	if cue=="click" and now-last_click<.045: return
	if cue=="click": last_click=now
	# A pick plus a synchronous placement is one contact, not two overlapping hits.
	if now-float(cue_times.get(cue,-10))<.075: return
	var family:=cue.trim_prefix("purchase-")
	var path:="res://assets/audio/interface/click.wav"
	var variant:=int(variants.get(cue,0))%int(config.variants)+1
	if family!="click": path=str(config.root)+cue+"-%d.wav" % variant
	if not clips.has(path):
		if not ResourceLoader.exists(path): return
		clips[path]=load(path)
	cue_times[cue]=now
	variants[cue]=variant
	last_clip=path
	var voice: AudioStreamPlayer=voices[played%voices.size()]
	voice.stop()
	voice.stream=clips[path]
	voice.volume_linear=.65 if cue.begins_with("purchase-") else .5
	voice.pitch_scale=pitch*randf_range(.985,1.015)
	voice.play()
	played+=1
	last_cue=cue

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused=false
		for voice in voices: voice.stop()
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN: focused=true
