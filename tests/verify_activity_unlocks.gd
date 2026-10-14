extends "res://tests/verify_workbench_scene.gd"
const Rules=preload("res://scripts/guest_activity_rules.gd")
const Journal=preload("res://scripts/guest_journal_data.gd")

func _ready() -> void:
	if "--unlocks-resume" in OS.get_cmdline_user_args():
		if not Supplies.save_path.begins_with("/tmp/"): get_tree().quit(2); return
		TimeManager.set_process(false); call_deferred("restored")
	else: super._ready()

func speak_to_taste() -> void:
	var steps:=0
	while StoryDialogue.phase=="story" and StoryDialogue.node_id!="_taste" and steps<80:
		steps+=1
		if StoryDialogue.current_choices().is_empty(): StoryDialogue.continue_talking()
		else: StoryDialogue.choose(StoryDialogue.current_choices()[0].id,StoryDialogue.revision)
	check(steps<80 and StoryDialogue.node_id=="_taste","chapter retains its original taste clue")

func run() -> void:
	var inventory: Dictionary=Supplies.inventory.serialize().duplicate(true)
	var research:=WorkbenchSession.research_state()
	var money: int=SlotWallet.balance
	for row in [["milo","milo_ferry",2],["hank","hank_lantern",3]]:
		var guest: String=row[0]; var id: String=row[1]; var target: int=row[2]
		for chapter in range(1,target+1):
			StoryDialogue.start_guest(guest); speak_to_taste(); await settle()
			check(not GuestActivities.progress(id).unlocked,"reading without acknowledging final clue cannot unlock: "+guest)
			StoryDialogue.continue_talking(); await settle()
			check(GuestActivities.progress(id).unlocked==(chapter==target),"exact zero-score milestone: "+guest+str(chapter))
		check(GuestActivities.satisfied_count(guest)==0,"no hidden high-score gate")
		check(StoryDialogue.progress[guest].activity_unlocks.has(id),"formal invitation mirrored to journal")
		check(not GuestActivities.progress(id).keepsake.is_empty(),"invitation gives keepsake")
		check(GuestActivities.book().rewards.is_empty(),"unlock does not claim first-clear reward")
		var archive:=JSON.stringify(Journal.conversations(guest,StoryDialogue.progress,StoryDialogue.catalog))
		check(archive.contains("渡河题") if guest=="milo" else archive.contains("货棚的草图"),"early invitation is in heard dialogue archive")
		if guest=="hank": check(not archive.contains("尼尔"),"early story does not reveal fifth-chapter name")
		StoryDialogue.start_guest(guest)
		check(StoryDialogue.episode.episode==target+1,"unlock does not skip next chapter")
		speak_to_taste(); StoryDialogue.continue_talking(); await settle()
		check(GuestActivities.progress(id).unlocked,"later story does not relock game")
	check(not GuestActivities.progress("ada_watch_memory").unlocked,"other activity remains independent")
	check(GuestActivities.requirement_text("milo_ferry")=="完成第 2 轮剧情" and GuestActivities.requirement_text("hank_lantern")=="完成第 3 轮剧情","presentation agrees with configured milestones")
	check(GuestActivities.requirement_text("ada_watch_memory").contains("2 次满意招待"),"Ada retains original quality gate")
	# Simulate an old save that has passed the milestones but has not received invitations.
	StoryDialogue.end_guest()
	check(GuestActivities._commit(Rules.fresh_book()),"old invitation-free activity ledger saved")
	for guest in ["milo","hank"]: StoryDialogue.progress[guest].erase("activity_unlocks")
	StoryDialogue._save()
	var story:=StoryDialogue.progress.duplicate(true)
	var path: String=Supplies.save_path
	Supplies.save_path=path+"/blocked.json"
	check(not GuestActivities.reconcile() and GuestActivities.book().unlocks.is_empty(),"failed durable write cannot grant an invitation")
	check(StoryDialogue.progress==story,"failed activity write does not change story flags")
	Supplies.save_path=path
	check(GuestActivities.reconcile(),"old progress receives eligible invitations without replay")
	var saved:=GuestActivities.book()
	for i in range(3): check(GuestActivities.reconcile() and GuestActivities.book()==saved,"reconcile is idempotent")
	# If the second save fails, keep the first durable receipt and retry only its mirror.
	StoryDialogue.progress.hank.erase("activity_unlocks"); StoryDialogue._save()
	var story_path: String=StoryDialogue.save_path
	StoryDialogue.save_path=story_path+"/blocked.json"
	check(not GuestActivities.reconcile() and GuestActivities.book()==saved,"journal-sync failure preserves activity receipt")
	StoryDialogue.save_path=story_path
	check(GuestActivities.reconcile() and StoryDialogue.progress.hank.activity_unlocks.has("hank_lantern"),"journal mirror retries safely")
	check(Supplies.inventory.serialize()==inventory and SlotWallet.balance==money and WorkbenchSession.research_state()==research,"unlock and migration change no materials, wallet or research rewards")
	home=load("res://scenes/home.tscn").instantiate(); add_child(home); await settle()
	for guest in ["milo","hank","ada"]:
		Navigation.journal_focus_guest=guest; Navigation.go_to(&"journal"); await settle()
		await capture("unlock-"+guest)
		Navigation.go_to(&"home"); await settle()
	home.queue_free(); await settle()
	print("ACTIVITY UNLOCKS: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func restored() -> void:
	await settle()
	for id in ["milo_ferry","hank_lantern"]:
		var guest: String=GuestActivities.config(id).guest_id
		check(GuestActivities.progress(id).unlocked and StoryDialogue.progress[guest].activity_unlocks.has(id),"independent invitation persists after restart")
		check(GuestActivities.begin(id) and GuestActivities.active.mode=="normal","recovered early invitation starts formal game")
		GuestActivities.end()
	check(GuestActivities.book().rewards.is_empty(),"restart grants no first-clear reward")
	check(not GuestActivities.progress("ada_watch_memory").unlocked,"restart does not unlock other guest")
	print("ACTIVITY UNLOCK RESTORE: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
