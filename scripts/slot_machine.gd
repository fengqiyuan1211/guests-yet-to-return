extends Control
signal close_requested
signal spin_finished(reward: int)
const Rules := preload("res://scripts/slot_rules.gd")
const Reel := preload("res://scripts/slot_reel.gd")
const Lever := preload("res://scripts/slot_lever.gd")
const Effects := preload("res://scripts/slot_effects.gd")
const Sounds := preload("res://scripts/slot_audio.gd")
var reels: Array[Control] = []
var stops: Array[int] = []
var busy := false
var lever: Button
var close_button: Button
var status: Label
var balance_label: Label
var payout_label: Label
var net_label: Label
var caption: Label
var effects: Control
var sounds: Node
var stop_labels: Array[Label] = []
var _tick_time := 0.0
var _symbols: Array = []
var rules_overlay: Control
var help_button: Button
var rules_close: Button
var _rules_previous_focus: Control

func _ready() -> void:
	_build()
	SlotWallet.balance_changed.connect(_balance_changed)
	_balance_changed(SlotWallet.balance)
	lever.grab_focus()
	if SlotWallet.recovered_payout >= 0:
		if SlotWallet.recovered_hidden:
			status.text = "恭喜你，触发隐藏大奖！"
			caption.text = "上次获奖记录已保存 · 限定奖品敬请期待"
			effects.jackpot = true
			for reel in reels:
				reel.result = Rules.HIDDEN_SYMBOL
				reel.strip[0] = Rules.HIDDEN_SYMBOL
				reel.queue_redraw()
		else:
			status.text = "上次未完成的转动已结算：+%d" % SlotWallet.recovered_payout
		SlotWallet.recovered_hidden = false
		SlotWallet.recovered_payout = -1
	if not SlotWallet.pending.is_empty():
		status.text = "上次结算未保存，点击拉杆重试"
	elif not SlotWallet.writable:
		status.text = SlotWallet.last_error

func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.035, 0.028, 0.985)
	place(shade, Rect2(0, 0, 1600, 900))
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			request_close()
	)
	label_at("酒馆里的小运气", Rect2(65, 39, 530, 45), 28, "ead5ac")
	label_at("BRASS & FORTUNE  /  蒸汽游艺机", Rect2(67, 91, 430, 28), 14, "a99775")
	close_button = Button.new()
	close_button.name = "CloseSlots"
	close_button.text = "返回酒馆  ×"
	place(close_button, Rect2(1350, 37, 186, 54))
	close_button.pressed.connect(request_close)
	help_button = Button.new()
	help_button.name = "AwardsHelp"
	help_button.text = "?"
	help_button.tooltip_text = "查看奖项设置"
	place(help_button, Rect2(1266, 37, 62, 54))
	help_button.pressed.connect(show_rules)
	panel_at(Rect2(65, 184, 308, 548), "261f17", "785e37")
	label_at("投  币  游  艺", Rect2(86, 210, 265, 43), 27, "eaca87", HORIZONTAL_ALIGNMENT_CENTER)
	texture_at(Reel.ICONS[1], Rect2(176, 279, 84, 84))
	label_at("20", Rect2(105, 367, 228, 88), 66, "f2d49a", HORIZONTAL_ALIGNMENT_CENTER)
	label_at("金 币 / 次", Rect2(105, 453, 228, 30), 20, "cbb080", HORIZONTAL_ALIGNMENT_CENTER)
	label_at("01   拉下红色拉杆\n02   等待转轮依次停稳\n03   查看本轮金币结算", Rect2(95, 520, 250, 139), 18, "c7b18c")
	label_at("点击右上角 ? 查阅奖项簿", Rect2(80, 675, 276, 32), 15, "a99473", HORIZONTAL_ALIGNMENT_CENTER)
	label_at("三枚「发」 · 100 倍大奖", Rect2(68, 753, 308, 35), 20, "deb877", HORIZONTAL_ALIGNMENT_CENTER)
	label_at("投入 20，最高返还 2,000 金币", Rect2(63, 797, 320, 29), 15, "a99473", HORIZONTAL_ALIGNMENT_CENTER)
	texture_at(preload("res://assets/slots/cabinet.svg"), Rect2(448, 66, 760, 780))
	label_at("幸 运 酒 馆", Rect2(600, 144, 456, 55), 38, "f5dd9c", HORIZONTAL_ALIGNMENT_CENTER)
	label_at("发发发", Rect2(645, 210, 365, 32), 18, "f5cd70", HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(3):
		var reel := Reel.new()
		reel.name = "Reel%d" % i
		reel.result = i
		place(reel, Rect2(554 + i * 189, 310, 170, 244))
		reels.append(reel)
		reel.stopped.connect(_on_reel_stopped.bind(i))
		stop_labels.append(label_at("0%d  ·  就绪" % (i + 1), Rect2(549 + i * 189, 582, 181, 27), 14, "ccad71", HORIZONTAL_ALIGNMENT_CENTER))
	status = label_at("拉动右侧拉杆，开启一轮好运", Rect2(573, 627, 510, 56), 21, "f0dca8", HORIZONTAL_ALIGNMENT_CENTER)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_at("每次  20  金币", Rect2(707, 730, 243, 40), 21, "382b1d", HORIZONTAL_ALIGNMENT_CENTER)
	caption = label_at("轻点红色拉杆  /  空格键也可启动", Rect2(548, 844, 560, 30), 16, "c2ad86", HORIZONTAL_ALIGNMENT_CENTER)
	texture_at(preload("res://assets/slots/mechanism.svg"), Rect2(1137, 312, 299, 340))
	lever = Lever.new()
	lever.name = "Lever"
	place(lever, Rect2(1195, 272, 118, 340))
	lever.pressed.connect(start_spin)
	label_at("拉 动", Rect2(1199, 242, 99, 31), 17, "d1b88b", HORIZONTAL_ALIGNMENT_CENTER)
	panel_at(Rect2(1260, 136, 279, 143), "211e17", "785e37")
	label_at("钱  袋  余  额", Rect2(1280, 153, 240, 30), 16, "b9a37a", HORIZONTAL_ALIGNMENT_CENTER)
	balance_label = label_at("300", Rect2(1280, 194, 240, 55), 36, "f2d49a", HORIZONTAL_ALIGNMENT_CENTER)
	label_at("锅 炉 压 力", Rect2(1255, 482, 153, 29), 14, "a89773", HORIZONTAL_ALIGNMENT_CENTER)
	panel_at(Rect2(1260, 645, 279, 179), "211e17", "785e37")
	label_at("本轮投入", Rect2(1278, 661, 120, 32), 18, "b8a483")
	label_at("20 金币", Rect2(1398, 661, 117, 32), 19, "ead3a7", HORIZONTAL_ALIGNMENT_RIGHT)
	label_at("本轮返还", Rect2(1278, 706, 120, 32), 18, "b8a483")
	payout_label = label_at("—", Rect2(1398, 706, 117, 32), 23, "f4d796", HORIZONTAL_ALIGNMENT_RIGHT)
	label_at("本轮净额", Rect2(1278, 753, 120, 32), 18, "b8a483")
	net_label = label_at("—", Rect2(1398, 753, 117, 32), 23, "f4d796", HORIZONTAL_ALIGNMENT_RIGHT)
	effects = Effects.new()
	place(effects, Rect2(0, 0, 1600, 900))
	sounds = Sounds.new()
	add_child(sounds)
	_build_rules()

func _build_rules() -> void:
	rules_overlay = Control.new()
	rules_overlay.name = "AwardsPaper"
	place(rules_overlay, Rect2(0, 0, 1600, 900))
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.009, 0.82)
	dim.size = size
	rules_overlay.add_child(dim)
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			hide_rules()
	)
	var paper := TextureRect.new()
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.texture = preload("res://assets/slots/parchment-western-v2.png")
	paper.position = Vector2(300, 35)
	paper.size = Vector2(1000, 830)
	paper.mouse_filter = Control.MOUSE_FILTER_STOP
	rules_overlay.add_child(paper)
	paper_label("L U C K Y   S A L O O N", Rect2(460, 165, 680, 28), 16, "775235", HORIZONTAL_ALIGNMENT_CENTER)
	paper_label("幸运酒馆 · 奖赏告示", Rect2(424, 199, 752, 54), 37, "442916", HORIZONTAL_ALIGNMENT_CENTER)
	paper_label("每次投入 20 金币  /  只计算转轮中间一行", Rect2(423, 256, 754, 30), 17, "705034", HORIZONTAL_ALIGNMENT_CENTER)
	paper_line(Vector2(421, 296), Vector2(1179, 296), 2.0)
	paper_line(Vector2(421, 300), Vector2(1179, 300), 0.7)
	for column in [["幸 运 图 案", 435, 231], ["三 个 相 同", 687, 221], ["正好两个相同", 929, 222]]:
		paper_label(column[0], Rect2(column[1], 305, column[2], 32), 18, "634022", HORIZONTAL_ALIGNMENT_CENTER)
	for i in range(5):
		var y := 341 + i * 61
		if i == 0:
			var wash := ColorRect.new()
			wash.color = Color(0.55, 0.17, 0.08, 0.085)
			wash.position = Vector2(421, y)
			wash.size = Vector2(758, 59)
			wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rules_overlay.add_child(wash)
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture = Reel.ICONS[i]
		icon.position = Vector2(446, y - 7)
		icon.size = Vector2(74, 74)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rules_overlay.add_child(icon)
		paper_label(Rules.NAMES[i], Rect2(534, y + 5, 110, 49), 23, "4e311a")
		paper_label("%s 金币" % Rules.TRIPLES[i], Rect2(687, y + 5, 221, 49), 26 if i == 0 else 23, "983d24" if i == 0 else "4e311a", HORIZONTAL_ALIGNMENT_CENTER)
		paper_label("%s 金币" % Rules.PAIRS[i], Rect2(929, y + 5, 222, 49), 22, "4e311a", HORIZONTAL_ALIGNMENT_CENTER)
		if i > 0:
			paper_line(Vector2(436, y), Vector2(1164, y), 1.0, "ad8958")
	paper_line(Vector2(421, 652), Vector2(1179, 652), 1.6)
	paper_label("三连优先 · 奖项不叠加 · 两连不限位置 · 其余组合返还 0", Rect2(429, 663, 742, 29), 17, "624225", HORIZONTAL_ALIGNMENT_CENTER)
	paper_label("表中为返还总额。本轮净额 = 返还金币 − 20 金币。", Rect2(429, 695, 742, 28), 16, "795938", HORIZONTAL_ALIGNMENT_CENTER)
	paper_label("—  三发齐聚，百倍赏金  —", Rect2(512, 731, 576, 29), 19, "943c25", HORIZONTAL_ALIGNMENT_CENTER)
	rules_close = Button.new()
	rules_close.name = "CloseAwards"
	rules_close.text = "收 好 告 示"
	rules_close.position = Vector2(677, 775)
	rules_close.size = Vector2(246, 47)
	rules_close.add_theme_font_size_override("font_size", 19)
	rules_overlay.add_child(rules_close)
	rules_close.focus_next = NodePath(".")
	rules_close.focus_previous = NodePath(".")
	rules_close.pressed.connect(hide_rules)
	rules_overlay.hide()

func paper_label(text: String, rect: Rect2, size_px: int, ink: String, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := label_at(text, rect, size_px, ink, align)
	label.reparent(rules_overlay, false)
	return label

func paper_line(from: Vector2, to: Vector2, width_px: float, ink := "795634") -> void:
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.width = width_px
	line.default_color = Color(ink)
	line.antialiased = true
	rules_overlay.add_child(line)

func show_rules() -> void:
	_rules_previous_focus = get_viewport().gui_get_focus_owner()
	rules_overlay.show()
	rules_close.grab_focus()

func hide_rules() -> void:
	rules_overlay.hide()
	if is_instance_valid(_rules_previous_focus):
		_rules_previous_focus.grab_focus()

func place(node: Control, rect: Rect2) -> void:
	node.position = rect.position
	node.size = rect.size
	add_child(node)

func label_at(text: String, rect: Rect2, size_px: int, ink: String, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", Color(ink))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = align
	place(label, rect)
	return label

func panel_at(rect: Rect2, fill: String, edge: String) -> void:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(edge)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	panel.add_theme_stylebox_override("panel", style)
	# Catch blank interior clicks, preserving the popup while viewing its rules.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	place(panel, rect)

func texture_at(texture: Texture2D, rect: Rect2) -> void:
	var view := TextureRect.new()
	view.texture = texture
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	place(view, rect)

func _balance_changed(value: int) -> void:
	balance_label.text = "%s 金币" % value
	if not busy:
		lever.disabled = (value < Rules.COST or not SlotWallet.writable) and SlotWallet.pending.is_empty()
		if value < Rules.COST:
			caption.text = "金币不足  ·  还需要 %d 金币" % (Rules.COST - value)

func start_spin() -> void:
	if busy or (is_instance_valid(rules_overlay) and rules_overlay.visible):
		return
	if not SlotWallet.pending.is_empty():
		_finish_spin()
		return
	_symbols = SlotWallet.begin_spin()
	if _symbols.is_empty():
		status.text = SlotWallet.last_error
		return
	busy = true
	stops.clear()
	lever.disabled = true
	close_button.disabled = true
	payout_label.text = "…"
	net_label.text = "…"
	status.text = "已投入 20 金币 · 锅炉启动"
	caption.text = "转轮停稳后结算，请稍候"
	effects.jackpot = false
	effects.active = true
	lever.animate_pull()
	sounds.play_sound("pull")
	await get_tree().create_timer(0.3).timeout
	status.text = "转动中…"
	for i in range(3):
		stop_labels[i].text = "0%d  ·  转动中" % (i + 1)
		reels[i].spin_to(int(_symbols[i]), i)

func _process(delta: float) -> void:
	if busy:
		_tick_time += delta
		if _tick_time > 0.13:
			_tick_time = 0.0
			sounds.play_sound("tick")

func _on_reel_stopped(index: int) -> void:
	if not busy or index in stops:
		return
	stops.append(index)
	stop_labels[index].text = "0%d  ·  %s" % [index + 1, Rules.NAMES[int(_symbols[index])]]
	sounds.play_sound("stop")
	if stops.size() == 3:
		await get_tree().create_timer(0.32).timeout
		_finish_spin()
	else:
		status.text = "%d / 3 已停稳" % stops.size()

func _finish_spin() -> void:
	var hidden := Rules.is_hidden(SlotWallet.pending)
	var reward := SlotWallet.settle_spin()
	busy = false
	effects.active = false
	close_button.disabled = false
	if reward < 0:
		status.text = "结算未保存 · 点击拉杆重试"
		caption.text = SlotWallet.last_error
		lever.disabled = false
		return
	payout_label.text = "+%d" % reward
	net_label.text = "%+d" % (reward - Rules.COST)
	net_label.add_theme_color_override("font_color", Color("b8d998") if reward >= Rules.COST else Color("d69879"))
	if hidden:
		status.text = "恭喜你，触发隐藏大奖！"
		effects.jackpot = true
		sounds.play_sound("jackpot")
	elif reward == 2000:
		status.text = "恭喜你，赢得 %d 金币" % reward
		effects.jackpot = true
		sounds.play_sound("jackpot")
	elif reward > 0:
		status.text = "恭喜你，赢得 %d 金币" % reward
		sounds.play_sound("coin")
	else:
		status.text = "很遗憾，本次未中奖"
	caption.text = "获奖记录已保存 · 限定奖品敬请期待" if hidden else "本轮已结算  ·  拉杆可开始下一轮"
	_balance_changed(SlotWallet.balance)
	if rules_overlay.visible:
		rules_close.grab_focus()
	else:
		lever.grab_focus()
	spin_finished.emit(reward)

func can_close() -> bool:
	return not busy and SlotWallet.pending.is_empty()

func request_close() -> void:
	if rules_overlay.visible:
		hide_rules()
		return
	if can_close():
		close_requested.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		request_close()
		get_viewport().set_input_as_handled()
