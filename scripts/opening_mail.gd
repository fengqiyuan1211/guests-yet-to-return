extends Control
## In-fiction mail reader. All content is local; nothing is sent to a real mailbox.
signal read_requested
signal closed
const UI=preload("res://scripts/opening_ui.gd")
var mail: Dictionary={}
var error_label: Label
var reader: RichTextLabel
var read_button: Button

func _ready() -> void:
	name="StoryMailReader"
	size=Vector2(1600,900)
	mouse_filter=Control.MOUSE_FILTER_STOP
	z_index=120
	var dim:=ColorRect.new()
	dim.size=size
	dim.color=Color(.025,.04,.055,.78)
	dim.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var p:=UI.panel(self,Rect2(180,102,1240,680))
	UI.label(p,Rect2(36,20,880,40),"收件箱  /  一封留给你的信",23,Color("bba887"))
	UI.button(p,Rect2(1000,18,205,44),"返回收件箱",func(): closed.emit(),true)
	UI.label(p,Rect2(38,81,1150,58),str(mail.subject),34)
	UI.label(p,Rect2(40,142,1140,34),"发件人："+str(mail.sender),21,Color("d1bc97"))
	var paper:=Panel.new()
	paper.position=Vector2(36,193)
	paper.size=Vector2(1168,337)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("f0e2c6")
	style.set_corner_radius_all(0)
	paper.add_theme_stylebox_override("panel",style)
	p.add_child(paper)
	reader=RichTextLabel.new()
	reader.position=Vector2(25,18)
	reader.size=Vector2(1115,300)
	reader.text=str(mail.body)
	reader.bbcode_enabled=false
	reader.selection_enabled=true
	reader.scroll_active=true
	reader.add_theme_font_override("normal_font",UI.FONT)
	reader.add_theme_font_size_override("normal_font_size",24)
	reader.add_theme_color_override("default_color",Color("372d22"))
	paper.add_child(reader)
	UI.label(p,Rect2(40,541,1150,32),str(mail.get("attachment","")),20,Color("d7bd8f"))
	UI.label(p,Rect2(40,600,420,30),"滚轮阅读全文 · Esc 收起邮件",18,Color("bba887"))
	read_button=UI.button(p,Rect2(610,589,590,52),str(mail.get("button","读完，继续")),func(): read_requested.emit(),true)
	error_label=UI.label(p,Rect2(40,645,1150,28),"",17,Color("ffd597"))
	# Keep focus in the document; reading remains an explicit button action.
	reader.focus_mode=Control.FOCUS_ALL
	reader.grab_focus()

func show_error(message: String) -> void:
	error_label.text=message
