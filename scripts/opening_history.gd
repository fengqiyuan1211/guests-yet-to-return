extends Control
## Read-only backlog: opening it never advances, chooses, or triggers story audio.
signal closed
const UI=preload("res://scripts/opening_ui.gd")
var entries: Array[Dictionary]=[]
var reader: RichTextLabel

func _ready() -> void:
	name="OpeningHistory"
	size=Vector2(1600,900)
	mouse_filter=Control.MOUSE_FILTER_STOP
	z_index=130
	var dim:=ColorRect.new()
	dim.size=size
	dim.color=Color(.025,.04,.055,.78)
	dim.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var p:=UI.panel(self,Rect2(165,68,1270,765))
	UI.label(p,Rect2(38,20,850,55),"一路说过的话",34)
	UI.label(p,Rect2(40,80,1000,32),"只记录已经走过的片段、你的选择和读过的邮件",20,Color("caba9e"))
	UI.button(p,Rect2(1040,25,190,48),"返回剧情 · H",func(): closed.emit(),true)
	reader=RichTextLabel.new()
	reader.position=Vector2(40,133)
	reader.size=Vector2(1190,567)
	reader.bbcode_enabled=true
	reader.selection_enabled=true
	reader.add_theme_font_override("normal_font",UI.FONT)
	reader.add_theme_font_size_override("normal_font_size",25)
	reader.add_theme_color_override("default_color",UI.INK)
	reader.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	p.add_child(reader)
	var chapter:=""
	for entry: Dictionary in entries:
		if not str(entry.chapter).is_empty() and entry.chapter!=chapter:
			chapter=entry.chapter
			reader.push_color(Color("ad9a7d"))
			reader.add_text("\n— "+chapter+" —\n\n")
			reader.pop()
		reader.push_color(Color("eac88d"))
		reader.add_text(OpeningFlow.protagonist_speaker(str(entry.speaker))+"\n")
		reader.pop()
		reader.add_text(str(entry.text)+"\n\n")
	if entries.is_empty(): reader.add_text("这里还没有留下对话。")
	UI.label(p,Rect2(40,716,1150,30),"滚轮查看之前的内容 · Esc / H 返回原处 · 不会重播音效",18,Color("caba9e"))
	reader.focus_mode=Control.FOCUS_ALL
	reader.grab_focus()
	call_deferred("_scroll_latest")

func _scroll_latest() -> void:
	if is_instance_valid(reader): reader.scroll_to_line(maxi(0,reader.get_line_count()-1))
