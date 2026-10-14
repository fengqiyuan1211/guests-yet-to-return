extends Control
signal close_requested
const Data = preload("res://scripts/guest_journal_data.gd")
const Preview = preload("res://scripts/workbench_drink_preview.gd")
const Gauge = preload("res://scripts/journal_score.gd")
const PAPER = preload("res://assets/codex/journal-paper-v1.png")
const INK = Color("49301e")
const MUTED = Color("684b2d")
const CREAM = Color("f3dfb6")
const TABS = ["资料", "对话回顾", "饮酒记录", "专属小游戏"]
const ATTRS = {"alcohol_intensity":"酒感", "sweetness":"甜度", "sourness":"酸度", "bitterness":"苦度"}
var profiles: Array = []
var selected_id := ""
var tab := 0
var root: Control
var sidebar: VBoxContainer
var profile_column: VBoxContainer
var content: VBoxContainer
var content_scroll: ScrollContainer
var summary: Label
var tab_buttons: Array[Button] = []
var guest_buttons: Dictionary = {}
var expanded: Dictionary = {}
var page := 0
const PER_PAGE := 8

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	profiles = Data.profiles()
	selected_id = StoryDialogue.guest_id
	if not Navigation.journal_focus_guest.is_empty():
		selected_id = Navigation.journal_focus_guest
		tab = 3
		Navigation.journal_focus_guest = ""
	if selected_id.is_empty():
		for profile in profiles:
			if StoryDialogue.is_known(profile.id):
				selected_id = profile.id
				break
	if selected_id.is_empty() and not profiles.is_empty(): selected_id = profiles[0].id
	_build()
	StoryDialogue.changed.connect(_refresh)
	WorkbenchSession.changed.connect(_refresh)
	CustomerService.changed.connect(_refresh)
	_refresh()

func _style(fill: Color, border:=Color("b28b53")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.set_content_margin_all(13)
	return box

func _place(node: Control, rect: Rect2) -> void:
	node.position = rect.position
	node.size = rect.size

func _label(parent: Node, text: String, px:=22, color:=INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", px)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _button(parent: Node, text: String, action: Callable, selected:=false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 44
	node.add_theme_font_size_override("font_size", 21)
	node.add_theme_color_override("font_color", CREAM)
	node.add_theme_color_override("font_hover_color", Color("fff4dd"))
	node.add_theme_stylebox_override("normal", _style(Color("916033") if selected else Color("59402b")))
	node.add_theme_stylebox_override("hover", _style(Color("946b3e")))
	node.add_theme_stylebox_override("pressed", _style(Color("3c291d")))
	node.add_theme_stylebox_override("focus", _style(Color(1,.8,.3,.12), Color("f0ce79")))
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(action)
	parent.add_child(node)
	return node

func _scroll(rect: Rect2) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_place(scroll, rect)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	scroll.add_child(column)
	return column

func _paper(rect: Rect2) -> void:
	var image := TextureRect.new()
	image.texture = PAPER
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(image)
	_place(image, rect)
	# Preserve the worn border, soften its printed motifs under the readable text.
	var reading := Panel.new()
	reading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reading.add_theme_stylebox_override("panel", _style(Color(.98,.89,.72,.66),Color(0,0,0,0)))
	root.add_child(reading)
	_place(reading, rect.grow(-23))

func _build() -> void:
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size = Vector2(1600,900)
	add_child(root)
	var leather := Panel.new()
	leather.add_theme_stylebox_override("panel", _style(Color("342319"), Color("b38a49")))
	root.add_child(leather)
	_place(leather, Rect2(242,128,1330,718))
	_paper(Rect2(465,138,523,696))
	_paper(Rect2(980,138,580,696))
	var seam := ColorRect.new()
	seam.color = Color(.22,.13,.06,.20)
	seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(seam)
	_place(seam, Rect2(975,151,9,670))
	_place(_label(root,"来 客 一 览",23,CREAM), Rect2(270,151,178,40))
	sidebar = _scroll(Rect2(259,208,190,550))
	_place(_label(root,"每一位客人，\n都有自己的故事。",18,CREAM), Rect2(267,771,180,56))
	_place(_label(root,"手 帐",38), Rect2(500,157,320,58))
	_place(_label(root,"G U E S T   J O U R N A L",16,MUTED), Rect2(501,214,410,30))
	profile_column = _scroll(Rect2(502,262,440,530))
	_place(_button(root,"返回 Esc",func(): close_requested.emit()), Rect2(1377,152,150,43))
	summary = _label(root,"",18,MUTED)
	_place(summary, Rect2(1013,157,348,45))
	for i in range(TABS.size()):
		var button := _button(root,TABS[i],_select_tab.bind(i))
		button.add_theme_font_size_override("font_size",19)
		_place(button,Rect2(1007+i*130,216,127,44))
		tab_buttons.append(button)
	content = _scroll(Rect2(1010,280,522,510))
	content_scroll = content.get_parent()
	_place(_label(root,"只记下已知的故事与真实出品 · 滚动翻阅",16,MUTED),Rect2(1010,799,521,28))

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _select_guest(id: String) -> void:
	selected_id = id
	page = 0
	expanded.clear()
	_refresh()

func _select_tab(index: int) -> void:
	tab = index
	page = 0
	_render_content()

func _refresh() -> void:
	if not is_instance_valid(root): return
	_clear(sidebar)
	guest_buttons.clear()
	for profile in profiles:
		var known := StoryDialogue.is_known(profile.id)
		var button := _button(sidebar,str(profile.name) if known else (str(profile.name)+" · 演示" if _has_demo(str(profile.id)) else "尚未相识"),_select_guest.bind(str(profile.id)),profile.id == selected_id)
		button.custom_minimum_size.y = 76
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if known:
			var portrait := AtlasTexture.new()
			portrait.atlas = load(profile.texture)
			var region: Array = profile.portrait
			portrait.region = Rect2(region[0],region[1],region[2],region[3])
			button.icon = portrait
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width",46)
			button.add_theme_constant_override("h_separation",12)
		guest_buttons[profile.id] = button
	_render_profile()
	_render_content()

func _profile() -> Dictionary:
	for profile in profiles:
		if profile.id == selected_id: return profile
	return {}

func _render_profile() -> void:
	_clear(profile_column)
	var profile := _profile()
	if profile.is_empty() or not StoryDialogue.is_known(selected_id):
		_label(profile_column,"？",100,MUTED)
		_label(profile_column,"尚未相识",30)
		_label(profile_column,"等他推开酒馆的门，再从一句问候开始。",23)
		_label(profile_column,"资料、偏好与故事会在相识后出现。",18,MUTED)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",15)
	profile_column.add_child(row)
	var art := TextureRect.new()
	var portrait := AtlasTexture.new()
	portrait.atlas = load(profile.texture)
	var region: Array = profile.portrait
	portrait.region = Rect2(float(region[0])-20,maxf(0,float(region[1])-130),float(region[2])+40,float(region[3])*1.65)
	art.texture = portrait
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(180,228)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(art)
	var intro := VBoxContainer.new()
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro.add_theme_constant_override("separation",12)
	row.add_child(intro)
	_label(intro,str(profile.name),36)
	_label(intro,str(profile.role),21,MUTED)
	_label(intro,str(profile.bio),21)
	_label(profile_column,"喜欢的口味",21,MUTED)
	_label(profile_column," · ".join(profile.get("preferences",[])),24,Color("506537"))
	_label(profile_column,"不喜欢的口味",21,MUTED)
	_label(profile_column," · ".join(profile.get("avoid",[])),23,Color("8b492f"))
	var groups := Data.conversations(selected_id,StoryDialogue.progress,StoryDialogue.catalog,WorkbenchSession.state)
	var count := 0
	for group in groups: count += group.lines.size()
	_button(profile_column,"对话回顾 · 已记录 %d 句  →" % count,_select_tab.bind(1))
	_label(profile_column,"重复对话只收录一次；只保留你读过的分支。",17,MUTED)

func _render_content() -> void:
	_clear(content)
	content_scroll.scroll_vertical = 0
	for i in range(tab_buttons.size()):
		tab_buttons[i].add_theme_stylebox_override("normal",_style(Color("916033") if i == tab else Color("59402b")))
	if not StoryDialogue.is_known(selected_id):
		summary.text = "尚未相识"
		if _has_demo(selected_id):
			_label(content,"内测期间，可提前体验小游戏。",21,MUTED)
			_activities()
		else: _label(content,"这一页，还在等待一位客人。",28)
		return
	var drinks := Data.drinks(selected_id,WorkbenchSession.state)
	var groups := Data.conversations(selected_id,StoryDialogue.progress,StoryDialogue.catalog,WorkbenchSession.state)
	summary.text = "已记录 %d 杯 · %d 段对话" % [drinks.size(),groups.size()]
	match tab:
		0:
			if drinks.is_empty(): _empty_drinks()
			else: _drink(drinks[0],true)
			_button(content,"查看全部饮酒记录  →",_select_tab.bind(2))
			_label(content,"最近聊过",26)
			if groups.is_empty(): _label(content,"还没有留下对话。",21,MUTED)
			else: _conversation(groups.back(),true)
			_button(content,"查看全部对话  →",_select_tab.bind(1))
			_activities()
		1:
			_label(content,"对话回顾",28)
			_label(content,"已读内容自动去重 · 保留你的回应",17,MUTED)
			if groups.is_empty(): _label(content,"先和这位客人聊一聊吧。",23)
			for group in groups: _conversation(group)
		2:
			_label(content,"饮酒记录",28)
			_label(content,"每杯独立留档，同款酒也分别记录。",18,MUTED)
			if drinks.is_empty(): _empty_drinks()
			page = clampi(page,0,maxi(0,ceili(drinks.size()/float(PER_PAGE))-1))
			for i in range(page*PER_PAGE,mini(drinks.size(),(page+1)*PER_PAGE)): _drink(drinks[i],false)
			if drinks.size()>PER_PAGE:
				var nav := HBoxContainer.new()
				nav.add_theme_constant_override("separation",10)
				content.add_child(nav)
				var back := _button(nav,"上一页",_change_page.bind(-1))
				back.disabled = page == 0
				_label(nav,"%d / %d" % [page+1,ceili(drinks.size()/float(PER_PAGE))],19)
				var forward := _button(nav,"下一页",_change_page.bind(1))
				forward.disabled = (page+1)*PER_PAGE >= drinks.size()
		3: _activities()

func _change_page(direction: int) -> void:
	page += direction
	_render_content()

func _empty_drinks() -> void:
	_label(content,"还没有为他留下成品记录。",23)
	_label(content,"聊天后为这位客人选酒、完成制作，这一杯就会留在这里。DIY 试调不会算作客人饮用。",20,MUTED)

func _card(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_style(Color(1,.94,.81,.28),Color("b28b53")))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	panel.add_child(column)
	return column

func _conversation(group: Dictionary, short:=false) -> void:
	var column := _card(content)
	_label(column,str(group.title),24)
	var lines: Array = group.lines
	var shown: Array = lines.slice(maxi(0,lines.size()-2)) if short else lines
	for line in shown:
		_label(column,("我：" if line.speaker == "player" else str(_profile().name)+"：")+str(line.text),20,Color("745033") if line.speaker == "player" else INK)

func _drink(record: Dictionary, overview: bool) -> void:
	var result: Dictionary = record.result
	var evaluation: Dictionary = result.get("evaluation",{})
	var recipe: Dictionary = result.get("recipe",{})
	var column := _card(content)
	var stamp: Dictionary = result.get("completed_at",{})
	var day := int(stamp.get("day",record.guest.get("day",0)))
	var minute := int(stamp.get("minute",-1))
	var when := "第 %d 天" % day if day>0 else "早期记录"
	if minute>=0: when += "  %02d:%02d" % [minute/60,minute%60]
	_label(column,when+"  ·  "+(("拒收 · 未收费" if result.get("customer_receipt",{}).get("status")=="rejected" and result.customer_receipt.total_paid==0 else "已交付并结算") if result.has("customer_receipt") else "已出品 · 尚未确认饮用"),16,MUTED)
	_label(column,str(recipe.get("name","未命名酒款")),29)
	_label(column,str(recipe.get("english_name","")),16,MUTED)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	column.add_child(row)
	var preview := Preview.new()
	preview.result = result.duplicate(true)
	preview.accent = Color(str(evaluation.get("color","b39465")))
	preview.custom_minimum_size = Vector2(150,180)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(preview)
	var values := VBoxContainer.new()
	values.add_theme_constant_override("separation",6)
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(values)
	_label(values,"本杯品质 · "+str(evaluation.get("title","未记录")),23,preview.accent.darkened(.40))
	for key in ATTRS:
		var value: Variant = evaluation.get("attributes",{}).get(key)
		var attribute := HBoxContainer.new()
		attribute.add_theme_constant_override("separation",8)
		values.add_child(attribute)
		var name_label := _label(attribute,str(ATTRS[key]),18)
		name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		name_label.custom_minimum_size.x = 43
		if value!=null:
			var gauge := Gauge.new()
			gauge.value = float(value)
			gauge.custom_minimum_size = Vector2(65,7)
			gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			attribute.add_child(gauge)
		var number := _label(attribute,WorkbenchSession.format_amount(float(value)) if value!=null else "未记录",18)
		number.size_flags_horizontal = Control.SIZE_SHRINK_END
		number.custom_minimum_size.x = 40
	if evaluation.get("score")!=null: _label(values,"出品评分 %s / 100" % str(evaluation.score),18,MUTED)
	var receipt: Dictionary = result.get("customer_receipt",{})
	if receipt.is_empty():
		_label(column,"满意程度：尚未评价   ·   客人评分：—",19)
		_label(column,"实付：未结算",21,Color("885437"))
	else:
		_label(column,"满意程度：%s · 客人评分 %s" % [receipt.satisfaction,("不评分" if receipt.score==null else "%.1f" % float(receipt.score))],20)
		_label(column,"实付 %d 金币" % int(receipt.total_paid),25,Color("805226"))
		_label(column,"酒款 %d + 小费 %d" % [int(receipt.base_paid),int(receipt.tip)],19,MUTED)
	if overview: return
	var opened: bool = expanded.get(record.id,false)
	_button(column,"收起本杯详情  ↑" if opened else "查看实际用料与制作评价  ↓",_toggle_drink.bind(str(record.id)))
	if opened:
		_label(column,"实际入杯用料",23)
		var vessel: Dictionary = result.get("contents",{})
		for material in vessel.get("contents",{}):
			_label(column,"%s  %s ml" % [WorkbenchSession.MATERIALS.get(material,{}).get("name",material),WorkbenchSession.format_amount(float(vessel.contents[material]))],19)
		for material in vessel.get("solids",{}):
			var item: Dictionary = WorkbenchSession.SOLIDS.get(material,{})
			_label(column,"%s  %s %s" % [item.get("name",material),str(vessel.solids[material]),item.get("unit","份")],19)
		_label(column,"出品冰 %s g · 装饰 %d 份" % [WorkbenchSession.format_amount(WorkbenchSession.ice_mass(vessel)),WorkbenchSession.garnishes(vessel).size()],19)
		for reason in evaluation.get("reasons",[]): _label(column,"· "+str(reason),18,MUTED)
		_label(column,"四项属性 0—100，酒感不等于 ABV。",16,MUTED)

func _toggle_drink(id: String) -> void:
	var previous_scroll := content_scroll.scroll_vertical
	expanded[id] = not expanded.get(id,false)
	_render_content()
	_restore_scroll.call_deferred(previous_scroll)

func _restore_scroll(value: int) -> void:
	if is_instance_valid(content_scroll): content_scroll.scroll_vertical = value

func _activities() -> void:
	_label(content,"专属小游戏",28)
	var items := Data.activities(selected_id,StoryDialogue.progress)
	if items.is_empty():
		_label(content,"这位客人还没有留下小游戏邀请。",22)
		return
	for item in items:
		var column := _card(content)
		_label(column,str(item.name),26)
		_label(column,str(item.description),21,MUTED)
		var available := Navigation.registered_pages.has(StringName(item.route))
		_label(column,"已解锁 · 正式邀请" if item.unlocked else ("内测演示 · 暂时开放" if item.demo else "尚未解锁"),22)
		var action := _button(column,"开始游戏  →" if available and item.accessible else ("尚未开放" if item.unlocked else "等待客人的邀请"),_launch_activity.bind(str(item.id)))
		action.disabled = not available or not item.accessible
		if item.demo and not item.unlocked: action.tooltip_text = "内测演示：暂时开放体验，不代表正式剧情已解锁；不推进剧情、不发放奖励。"
		if item.id in preload("res://scripts/guest_activity_rules.gd").IDS:
			var info: Dictionary=GuestActivities.progress(item.id)
			_label(column,"邀请进度："+GuestActivities.requirement_text(item.id,true),20)
			if int(info.required_chapters)<StoryDialogue.catalog.get(selected_id,[]).size():
				_label(column,"小游戏解锁后，后面的来访故事仍会继续。",19,MUTED)
			if not info.keepsake.is_empty():
				_label(column,"已获得纪念物："+str(info.keepsake.name),23)
				_label(column,str(info.keepsake.description),19,MUTED)
				_label(column,str(GuestActivities.config(item.id).invitation),21)
			if not info.reward.is_empty():
				var recipe:=preload("res://scripts/research_data.gd").legendary(info.reward.recipe_id)
				_label(column,"首通已领取：《%s》配方 · 灵感 +%d" % [recipe.get("name",""),info.reward.inspiration],21,Color("506537"))
			else: _label(column,"本小游戏正式首通：专属配方＋%d 点研发灵感；演示不发奖。" % int(item.get("reward_inspiration",0)),18,MUTED)
		if item.id=="stick_minigame":
			_label(column,"这里可随时练习；正式邀请与纪念奖励在酒馆剧情中触发。",19,MUTED)

func _launch_activity(id: String) -> void:
	# Check again at click time; presentation state does not grant access.
	for item in Data.activities(selected_id,StoryDialogue.progress):
		if item.id == id and item.accessible and Navigation.registered_pages.has(StringName(item.route)):
			if item.route=="stick_badminton":
				Navigation.memory_match_context={"mode":"practice"}
				Navigation.memory_from_journal=true
			Navigation.go_to(StringName(item.route))

func _has_demo(id: String) -> bool:
	for item in Data.activities(id,StoryDialogue.progress):
		if item.demo: return true
	return false
