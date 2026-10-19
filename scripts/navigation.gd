extends Node
## Stable route IDs. Register a PackedScene to replace an entry preview.
signal route_requested(route_id: StringName)
signal page_changed(route_id: StringName)

const ROUTES: Dictionary = {
	&"yellow_ski": {"title":"奶龙大冒险"},
	&"milo_ferry": {"title":"把路画到家 · 雨后渡口"},
	&"ada_watch_memory": {"title":"慢半拍的下午"},
	&"hank_lantern": {"title":"灯下有名 · 风沙前的货棚"},
	&"journal": {"title": "手帐"},
	&"stick_demo": {"title": "童年拾忆 · 内测演示"},
	&"stick_badminton": {"title": "童年拾忆"},
	&"drink_selection": {"title": "为客人选一杯"},
	&"settings": {"title": "设置"},
	&"backpack": {"title": "物品栏"},
	&"slots": {"title": "幸运酒馆"},
	&"shop": {"title": "港口货栈", "subtitle": "船刚靠岸，今天的货都在这儿了。", "tabs": ["原酒", "配料", "装饰品"], "notes": ["原酒按用量消耗，可以在这里补货。", "果汁、糖浆和其他配料为酒增添风味。", "为出杯选一份合适的装饰。"], "next": "货架陈列 · 购入补货"},
	&"codex": {"title": "调酒师图鉴", "subtitle": "每点亮一页，便多一种招待客人的方式。", "tabs": ["已点亮", "未点亮"], "notes": ["这里将展示已经解锁的酒谱：材料用量、所需器材、杯型、装饰与制作步骤。", "灰色酒谱会列出尚缺的材料。备齐后点亮；材料耗尽不会让图鉴重新变灰。"], "next": "酒谱卡片 · 缺项提示 · 配方详情"},
	&"research": {"title": "配方研发室", "subtitle": "把一个想法，变成可以再次调出的味道。", "tabs": ["调配新酒", "我的配方"], "notes": ["选择材料与用量、制作技法、杯型和装饰，试调属于你的配方。", "保存酒名、标签、材料用量和完整步骤。之后可以按记录复现，并加入酒单。"], "next": "材料选择 · 用量调整 · 配方保存"},
	&"menu": {"title": "今晚的酒单", "subtitle": "每一杯，都由你决定。", "tabs": ["上架酒款", "待上架"], "notes": ["从已点亮的酒谱中选择上架酒款，售价由配方成本统一确定。", "从已点亮的经典酒和保存的原创配方中选择，安排今晚的酒单。"], "next": "上架管理 · 配方售价"},
	&"reviews": {"title": "客人的留言", "subtitle": "好手艺，会被记住。", "tabs": ["店铺评价", "营业记录"], "notes": ["客人会根据需求匹配、出品与等待时间留下评价，店铺评分会影响之后的客源。", "这里将记录每天的收入、消耗与服务情况，帮助你安排下一晚的营业。"], "next": "评价结算 · 客源变化 · 营业记录"},
	&"mixing": {"title": "调酒工作台", "subtitle": "从量取第一份材料开始。", "tabs": ["当前订单"], "notes": ["后续将在这里按现实配方完成量取、加料、制作、出杯与装饰，并按需求和完成情况结算。"], "next": "真实制作流程 · 出品判定 · 订单结算"},
	&"help": {"title": "欢迎来到你的酒馆", "subtitle": "落日已至，第一杯酒就从这里开始。", "tabs": ["操作指引"], "notes": ["点击左侧木牌进入图鉴、商店、研发、酒单或手帐。点击「开始营业」可以预览营业状态，再前往调酒台。当前版本用于查看主页和入口，尚未进行真实订单结算。\n\n支持鼠标与触屏点击。按 Esc 返回主页；横屏体验更舒适。"], "next": "主页预览 · 第一版"}
}

var registered_pages: Dictionary = {}
var current_route: StringName = &"home"
var journal_focus_guest := ""
var memory_from_journal := false
var memory_resume_running: Variant = null
var memory_match_context: Dictionary = {}
var research_view := "entry"
var research_base_id := ""

func register_page(route_id: StringName, scene: PackedScene) -> void:
	assert(ROUTES.has(route_id), "Unknown route: %s" % route_id)
	registered_pages[route_id] = scene

func go_to(route_id: StringName) -> void:
	# Hidden pages cannot be reached through a stale button or old navigation state.
	if route_id == &"stick_demo": return
	if route_id == &"stick_badminton":
		var allowed := CustomerService.can_award_memory(str(CustomerService.state.active.get("id","")))
		for item in preload("res://scripts/guest_journal_data.gd").activities("stick",StoryDialogue.progress):
			allowed = allowed or item.unlocked
		if not allowed: return
	if route_id in [&"milo_ferry", &"ada_watch_memory", &"hank_lantern", &"yellow_ski"]:
		if not GuestActivities.progress(str(route_id)).get("unlocked",false): return
	if route_id==&"reviews": route_id=&"journal"
	if current_route == &"settings" and GameSession.resetting:
		return
	if current_route == &"slots" and route_id != &"slots" and not SlotWallet.pending.is_empty():
		return
	if route_id != &"home" and not ROUTES.has(route_id):
		push_warning("Unknown route: %s" % route_id)
		return
	current_route = route_id
	route_requested.emit(route_id)
	page_changed.emit(route_id)
