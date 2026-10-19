extends Control
## A conversation can be interrupted at any line; only observed lines enter the journal.
signal closed
const UI=preload("res://scripts/opening_ui.gd")
var topic := "merchant_intro"
var preview_only := false
var index := 0
var text_label: Label
var next_button: Button
var error_label: Label
var reader: Control
var local_history: Array[Dictionary] = []

func _ready() -> void:
	name="MerchantConversation"
	size=Vector2(1600,900)
	mouse_filter=Control.MOUSE_FILTER_STOP
	z_index=120
	var dim:=ColorRect.new()
	dim.size=size
	dim.color=Color(0.04,0.06,0.07,.54)
	dim.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel:=UI.panel(self,Rect2(110,535,1380,325))
	UI.label(panel,Rect2(35,18,910,38),"港口货栈 · "+("旧单背面" if topic=="old_invoice" else "认识这里的人"),23,Color("eac88d"))
	text_label=UI.label(panel,Rect2(35,76,1290,146),"",28)
	text_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	UI.button(panel,Rect2(35,243,210,46),"稍后再聊 · Esc",_close,true)
	UI.button(panel,Rect2(270,243,180,46),"已读对话 H",_history,true)
	next_button=UI.button(panel,Rect2(1025,243,310,46),"继续 · 空格",_advance,true)
	error_label=UI.label(self,Rect2(150,870,1300,28),"",18)
	if not preview_only: index=int(Relationships.state.cursors.get(topic,0))
	_show_line()

func _show_line() -> void:
	var lines: Array=Relationships.config.topics[topic]
	if index>=lines.size(): _close(); return
	if not preview_only and not Relationships.observe_line(topic,index):
		error_label.text=Relationships.last_error if not Relationships.last_error.is_empty() else "这段话暂时无法继续，请返回后再试。"
		next_button.disabled=true
		return
	var line: Dictionary=lines[index]
	text_label.text=str(line.speaker)+"\n"+str(line.text)
	local_history.append({"chapter":"港口货栈","speaker":line.speaker,"text":line.text})
	next_button.text="收进手帐 · 空格" if index==lines.size()-1 else "继续 · 空格"
	next_button.grab_focus()
	if line.get("evidence",false):
		var note:=TextureRect.new()
		note.texture=preload("res://assets/pixel_b/paper.svg")
		note.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		note.position=Vector2(540,160)
		note.size=Vector2(520,290)
		note.mouse_filter=Control.MOUSE_FILTER_IGNORE
		add_child(note)
		UI.label(note,Rect2(45,35,430,45),"旧送货单 · 背面",24,Color("715236"))
		UI.label(note,Rect2(75,112,370,60),"留 到 风 停",44,Color("493521"))
		UI.label(note,Rect2(45,225,430,30),"已看见这句话；纸仍留在老板娘这里。",17,Color("715236"))

func _advance() -> void:
	if is_instance_valid(reader) or next_button.disabled: return
	if not preview_only and not Relationships.advance_topic(topic,index):
		error_label.text=Relationships.last_error
		return
	index+=1
	if index>=Relationships.config.topics[topic].size(): _close()
	else: _show_line()

func _close() -> void:
	closed.emit()
	queue_free()

func _history() -> void:
	if is_instance_valid(reader): return
	reader=preload("res://scripts/opening_history.gd").new()
	if preview_only: reader.entries.assign(local_history)
	else:
		for group: Dictionary in Relationships.merchant_history():
			for line: Dictionary in group.lines:
				reader.entries.append({"chapter":group.title,"speaker":"我" if line.speaker=="player" else "老板娘","text":line.text})
	reader.closed.connect(_close_history)
	add_child(reader)

func _close_history() -> void:
	if is_instance_valid(reader): reader.queue_free()
	reader=null
	next_button.grab_focus()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey: return
	var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
	if key not in [KEY_SPACE,KEY_ESCAPE,KEY_H]: return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo: return
	if is_instance_valid(reader):
		if key in [KEY_ESCAPE,KEY_H]: _close_history()
	elif key==KEY_ESCAPE: _close()
	elif key==KEY_H: _history()
	else: _advance()
