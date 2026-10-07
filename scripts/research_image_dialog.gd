extends Control
signal saved
const Client=preload("res://scripts/diy_image_client.gd")
const RequestBuilder=preload("res://scripts/research_image_request.gd")
const Preview=preload("res://scripts/workbench_drink_preview.gd")
const FONT=preload("res://assets/fonts/NotoSerifSC.ttf")
var session: Dictionary={}
var surface: Control
var client: Node
var title: LineEdit
var english: LineEdit
var story: TextEdit
var notes: TextEdit
var status: Label
var art: TextureRect
var original_preview: Control
var generate: Button
var accept: Button
var picture: Dictionary={}
var request: Dictionary={}
var content_hash:=""
var form_hash:=""
var cache_path:=""
var pending_info: Dictionary={}
var locked:=false
var rule_preview_data := ""

func _capture_rule_preview() -> String:
	if not rule_preview_data.is_empty(): return rule_preview_data
	# Reuse the exact saved reference on retries so request identity stays stable.
	if request.get("preview_image", "").begins_with("data:image/png;base64,"):
		rule_preview_data=request.preview_image
		return rule_preview_data
	if DisplayServer.get_name()=="headless": return ""
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(768,768)
	viewport.disable_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background:=ColorRect.new()
	background.size=Vector2(768,768)
	background.color=Color.WHITE
	viewport.add_child(background)
	var reference:=Preview.new()
	reference.reference_only=true
	reference.size=Vector2(768,768)
	reference.result=session.result.duplicate(true)
	reference.result.erase("image_path")
	viewport.add_child(reference)
	reference.set_process(false)
	reference.clock=0.0
	await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image()
	if image!=null and not image.is_empty():
		rule_preview_data="data:image/png;base64,"+Marshalls.raw_to_base64(image.save_png_to_buffer())
	viewport.queue_free()
	return rule_preview_data

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var veil:=ColorRect.new()
	veil.color=Color(0.07,0.045,0.025,.9)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	surface=Control.new()
	surface.size=Vector2(1600,900)
	add_child(surface)
	var panel:=Panel.new()
	panel.position=Vector2(190,65)
	panel.size=Vector2(1220,770)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("eed9b3")
	style.border_color=Color("b58a48")
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel",style)
	surface.add_child(panel)
	_label(Rect2(235,95,1030,48),"把这一杯留在酒谱里",31)
	_button(Rect2(1330,91,48,45),"×",func(): queue_free())
	_label(Rect2(235,153,650,38),"实际配方已经记下。给它一个名字，再画成手绘酒图。",19)
	title=_line(Rect2(235,217,610,43),"酒名（必填）")
	english=_line(Rect2(235,277,610,43),"英文名（可选）")
	title.max_length=40
	english.max_length=70
	story=_editor(Rect2(235,349,610,130),"关于这杯酒的故事或心情（可选，最多1000字）")
	notes=_editor(Rect2(235,506,610,113),"复做笔记（可选，最多500字）")
	var preview:=Preview.new()
	preview.position=Vector2(897,200)
	preview.size=Vector2(430,419)
	preview.result=session.result.duplicate(true)
	original_preview=preview
	surface.add_child(preview)
	art=TextureRect.new()
	art.position=preview.position
	art.size=preview.size
	art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	surface.add_child(art)
	status=_label(Rect2(235,643,1090,73),"生成完成后先检查杯型、颜色与装饰，再确认保存。",20)
	generate=_button(Rect2(235,737,290,51),"生成手绘酒图",_generate)
	accept=_button(Rect2(550,737,290,51),"确认图片并保存成品",_save)
	accept.disabled=true
	_button(Rect2(1058,737,270,51),"稍后再画",func(): queue_free())
	client=Client.new()
	var config: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/diy_image_service.json"))
	if config is Dictionary: client.service_url=str(config.get("service_url",client.service_url))
	var override:=ConfigFile.new()
	if override.load("user://diy_image_service.cfg")==OK:
		client.service_url=str(override.get_value("service","url",client.service_url))
		client.service_token=str(override.get_value("service","token",""))
	add_child(client)
	client.image_ready.connect(_ready_image)
	client.generation_failed.connect(_failed)
	client.job_changed.connect(func(info: Dictionary):
		pending_info=info.duplicate(true)
		_cache()
		if info.get("status") in ["queued","running"]: status.text="正在画这杯酒，完成后会出现在右侧。")
	cache_path="user://diy_cocktails/drafts/"+str(session.result.drink_id).sha256_text()+".json"
	_restore()
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	var factor:=minf(size.x/1600,size.y/900)
	surface.scale=Vector2.ONE*factor
	surface.position=(size-surface.size*factor)*.5

func _label(rect: Rect2,value: String,px: int) -> Label:
	var node:=Label.new()
	node.position=rect.position
	node.size=rect.size
	node.text=value
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_override("font",FONT)
	node.add_theme_font_size_override("font_size",px)
	node.add_theme_color_override("font_color",Color("594129"))
	surface.add_child(node)
	return node

func _button(rect: Rect2,value: String,action: Callable) -> Button:
	var node:=Button.new()
	node.position=rect.position
	node.size=rect.size
	node.text=value
	node.focus_mode=Control.FOCUS_NONE
	node.add_theme_font_override("font",FONT)
	node.add_theme_font_size_override("font_size",21)
	for state in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("69462b") if state=="normal" else Color("876039") if state!="disabled" else Color("9a8a72")
		style.border_color=Color("b58a48")
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		node.add_theme_stylebox_override(state,style)
	node.pressed.connect(action)
	surface.add_child(node)
	return node

func _line(rect: Rect2,hint: String) -> LineEdit:
	var node:=LineEdit.new()
	node.position=rect.position
	node.size=rect.size
	node.placeholder_text=hint
	node.add_theme_font_size_override("font_size",22)
	surface.add_child(node)
	return node

func _editor(rect: Rect2,hint: String) -> TextEdit:
	var node:=TextEdit.new()
	node.position=rect.position
	node.size=rect.size
	node.placeholder_text=hint
	node.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	node.add_theme_font_size_override("font_size",21)
	surface.add_child(node)
	return node

func _form() -> Dictionary:
	return {"name":title.text.strip_edges(),"english_name":english.text,"story":story.text,"notes":notes.text}

func _lock(value: bool) -> void:
	locked=value
	title.editable=not value and session.mode!="research_legendary"
	english.editable=not value
	story.editable=not value
	notes.editable=not value
	generate.disabled=value

func _generate() -> void:
	if locked: return
	if title.text.strip_edges().is_empty() or story.text.length()>1000 or notes.text.length()>500:
		status.text="请填写酒名；故事最多1000字，笔记最多500字。"
		return
	_lock(true)
	status.text="正在准备这杯酒的用料参考……"
	var preview_data: String=await _capture_rule_preview()
	if preview_data.is_empty():
		_lock(false)
		status.text="酒杯参考图暂时未能生成，请重新打开此页后重试。"
		return
	var next:=RequestBuilder.build(session,title.text.strip_edges(),story.text)
	next.preview_image=preview_data
	var hash:=JSON.stringify(next).sha256_text()
	# Re-submit the same request id after a lost response or scene change: no second charge.
	if request.is_empty() or content_hash!=hash or not picture.is_empty() or pending_info.get("provider_terminal",false):
		request=next
		request.request_id=client._uuid_v4()
	content_hash=hash
	form_hash=JSON.stringify(_form()).sha256_text()
	picture={}
	accept.disabled=true
	_lock(true)
	_cache()
	var services:=get_node_or_null("/root/LocalServices")
	if services!=null:
		status.text="正在准备酒图服务……"
		var ready: bool=await services.ensure_ready("image")
		if not is_inside_tree() or is_queued_for_deletion(): return
		if not ready:
			_lock(false)
			status.text=services.failure_message("image")
			return
	status.text="正在提交手绘酒图……"
	client.generate_drink(request)

func _ready_image(id: String, revision: int, path: String, texture: Texture2D, info: Dictionary) -> void:
	if id!=session.result.drink_id or revision!=1: return
	picture={"path":path,"source_drink_id":id,"task_id":info.task_id,"recipe_hash":info.recipe_hash,"style_id":Client.STYLE_ID,"confirmed":false}
	art.texture=texture
	original_preview.hide()
	_lock(false)
	accept.disabled=false
	generate.text="重新生成酒图"
	status.text="检查右侧的手绘酒图。确认后保存实际用量、属性和图片。重新生成会再次调用绘图服务。"
	_cache()

func _failed(_code: String,message: String) -> void:
	_lock(false)
	status.text=message+"  这杯酒仍保留着，可稍后重试。"
	generate.text="重试生成"
	_cache()

func _save() -> void:
	if picture.is_empty(): return
	if form_hash!=JSON.stringify(_form()).sha256_text():
		status.text="文字已经修改，请重新生成与它对应的酒图后再保存。"
		return
	var payload:=_form()
	picture.confirmed=true
	payload.image=picture.duplicate(true)
	var kind:="save_legendary_image" if session.mode=="research_legendary" else "save_research"
	if WorkbenchSession.command("save-image-"+str(Time.get_ticks_usec()),str(session.id),kind,payload):
		saved.emit()
		queue_free()
	else: status.text=WorkbenchSession.last_error

func _cache() -> void:
	if cache_path.is_empty(): return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_path.get_base_dir()))
	var file:=FileAccess.open(cache_path+".tmp",FileAccess.WRITE)
	if file==null: return
	file.store_string(JSON.stringify({"cup_hash":JSON.stringify(session.result).sha256_text(),"form":_form(),"request":request,"content_hash":content_hash,"form_hash":form_hash,"picture":picture,"job":pending_info}))
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(cache_path+".tmp"),ProjectSettings.globalize_path(cache_path))

func _restore() -> void:
	if session.mode=="research_legendary":
		title.text=session.recipe.name
		english.text=session.recipe.english_name
		story.text=session.recipe.get("story","")
		title.editable=false
	if not FileAccess.file_exists(cache_path): return
	var old: Variant=JSON.parse_string(FileAccess.get_file_as_string(cache_path))
	if not old is Dictionary or old.get("cup_hash")!=JSON.stringify(session.result).sha256_text(): return
	var form: Dictionary=old.get("form",{})
	title.text=str(form.get("name",""))
	english.text=str(form.get("english_name",""))
	story.text=str(form.get("story",""))
	notes.text=str(form.get("notes",""))
	request=old.get("request",{})
	content_hash=str(old.get("content_hash",""))
	form_hash=str(old.get("form_hash",""))
	pending_info=old.get("job",{})
	picture=old.get("picture",{})
	if preload("res://scripts/research_data.gd").valid_image(picture) and FileAccess.file_exists(str(picture.get("path",""))) and Image.load_from_file(picture.path)!=null:
		art.texture=ImageTexture.create_from_image(Image.load_from_file(picture.path))
		original_preview.hide()
		accept.disabled=false
		generate.text="重新生成酒图"
		status.text="上次画好的酒图还在，可检查后直接保存。"
	else:
		picture={}
		if not request.is_empty():
			generate.text="继续查看酒图"
			status.text="已保留上次的出图任务，点击继续查看，无需重新提交一杯酒。"

func _exit_tree() -> void:
	if is_instance_valid(title): _cache()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
