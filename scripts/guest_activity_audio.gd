extends Node
## Local voices on the shared SFX bus. Stop immediately on pause/exit.
var voices: Array[AudioStreamPlayer]=[]
var clips: Dictionary={}
var times: Dictionary={}
var serial:=0
var enabled:=true
func _ready() -> void:
	for i in range(8):
		var voice:=AudioStreamPlayer.new(); voice.bus=&"SFX"; add_child(voice); voices.append(voice)
func cue(name: String) -> void:
	if not enabled: return
	var now:=Time.get_ticks_msec()/1000.0
	if now-float(times.get(name,-10))<(.18 if name=="scrape" else .07): return
	times[name]=now
	var paths: Dictionary={"pick":"wood","place":"wood","dock":"wood","reject":"wood","metal":"metal","rotate":"metal","snap":"metal","scrape":"metal","step":"wood","crate_lamp":"metal","crate_rope":"leaf"}
	var path: String
	if paths.has(name): path="res://assets/audio/interface/foley/%s-%d.wav" % [paths[name],serial%2+1]
	else: path="res://assets/audio/activities/%s.wav" % ("water" if name=="crate_oil" else name)
	if not ResourceLoader.exists(path): return
	if not clips.has(path): clips[path]=load(path)
	var voice:=voices[serial%voices.size()]; serial+=1; voice.stop(); voice.stream=clips[path]
	var gain: float={"pick":-14,"place":-10,"dock":-11,"reject":-19,"rotate":-18,"snap":-14,"scrape":-30,"step":-22,"water":-20,"tick":-25,"success":-15,"wind":-25}.get(name,-16)
	voice.volume_db=gain
	voice.pitch_scale=float({"pick":1.18,"dock":.76,"reject":.64,"rotate":1.5,"snap":1.18,"scrape":.7,"step":.65}.get(name,1.0))*[.97,1.0,1.03][serial%3]
	voice.play()
func suspend(value: bool) -> void:
	enabled=not value
	if value:
		for voice in voices: voice.stop()
