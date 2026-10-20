extends RefCounted
## Replay uses fresh sidecar files, never the player's economy/story files.
## Snapshots restore in-memory services when leaving the replay; a restart loads normal files.
var active := false
var snapshots: Dictionary = {}
var inventory: Dictionary = {}

func start() -> bool:
	if active: return true
	if not SlotWallet.pending.is_empty() or not Supplies._pending.is_empty():
		OpeningFlow.last_error="请先完成当前交易，再体验教学。"
		return false
	var services := [GameSession, SlotWallet, StoryDialogue, MenuCatalog, Supplies, WorkbenchSession, CustomerService, PlayModes, Relationships, GuestActivities, TimeManager, Navigation]
	var folder := OpeningFlow.save_path+"-world-"+str(Time.get_unix_time_from_system()).replace(".","-")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK: return false
	CustomerService._cancel_request()
	for service: Node in services:
		var saved: Dictionary = {}
		for property: Dictionary in service.get_property_list():
			if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
			var value: Variant = service.get(property.name)
			if typeof(value) in [TYPE_NIL, TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL]: continue
			saved[property.name] = value.duplicate(true) if value is Dictionary or value is Array else value
		snapshots[service] = saved
	inventory=Supplies.inventory.serialize()
	# Redirect every persisted gameplay service before emitting any reset signals.
	for service: Node in services:
		var field := "path" if service == PlayModes else "save_path"
		if snapshots[service].has(field): service.set(field,folder+"/"+str(service.name)+".json")
	active=true
	GameSession.home=null
	WorkbenchSession.tutorial_active=false
	var checkpoint: Dictionary=OpeningFlow.state.duplicate(true)
	var ok := GameSession._finish_restart()
	if ok: ok=OpeningFlow._commit(checkpoint)
	if ok: ok=MenuCatalog.unlock_recipe("echo_world")
	TimeManager.set_running(false)
	if not ok:
		restore()
		OpeningFlow.state=checkpoint
		OpeningFlow.last_error="体验存档未能初始化，原来的经营记录已保留。"
	return ok

func restore() -> void:
	if not active: return
	CustomerService._cancel_request()
	GameSession.home=null
	# No changed signals until every service and all save paths have been restored.
	for service: Node in snapshots:
		for key: String in snapshots[service]: service.set(key,snapshots[service][key])
	Supplies.inventory.restore(inventory)
	GameSession.home=null
	TimeManager.set_running(false)
	active=false
	snapshots.clear()
