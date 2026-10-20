extends Node
const Rules = preload("res://scripts/stick_memory_rules.gd")
const Model = preload("res://scripts/stick_badminton_model.gd")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	if not GameSession.save_path.begins_with("/tmp/"): get_tree().quit(2); return
	await get_tree().process_frame
	TimeManager.set_process(false)
	GameSession.set_process(false)
	check(StoryDialogue.catalog.stick.size() == 3, "demo has exactly three visits")
	for guest in ["milo", "ada", "hank", "yellow_creature"]:
		check(StoryDialogue.catalog[guest].size() == 5, "other guest retains five visits: " + guest)
	check(Rules.TARGET == 3, "current match target is three")
	var model := Model.new()
	model.begin("memory-release", 0, 7)
	model.player_actions = 1
	for point in range(3):
		model.phase = "rally"
		model._point(0, "test")
		check((model.phase == "finished") == (point == 2), "match ends only on third point")
	var result := model.result()
	check(Rules.valid_result(result), "three-point win accepted")
	var old := result.duplicate(true)
	old.erase("target_score")
	old.player_score = 5
	check(Rules.valid_result(old, true), "old five-point result readable")
	check(not Rules.valid_result(old), "new submissions cannot use old target")
	var research := preload("res://scripts/research_data.gd").fresh()
	research.memory_matches[old.match_id] = old
	check(preload("res://scripts/research_data.gd").valid(research), "old match survives warehouse validation")
	if "--demo-resume" in OS.get_cmdline_user_args():
		check(GameSession.writable and StoryDialogue.writable, "legacy save remains writable")
		check(StoryDialogue.progress.stick.completed == 3, "legacy five chapters map to three")
		check(StoryDialogue.progress.stick.archive.size() == 1, "heard archive preserved")
		check(StoryDialogue.guest_id == "stick" and StoryDialogue.phase == "idle", "retired active chapter safely resumes")
		check(StoryDialogue.episode.id == "stick_03", "active session uses final demo chapter")
		check(GameSession.save_game(), "migrated snapshot can be saved")
	else:
		for completed in range(6):
			var fixture := {"version":1,"guests":{"stick":{"completed":completed,"heard":{},"pending":{},"content_revision":"stick-v0.3"}}}
			StoryDialogue.upgrade_demo_progress(fixture)
			check(StoryDialogue._valid_save(fixture), "old progress validates: " + str(completed))
			check(fixture.guests.stick.completed == mini(completed,3), "completed progress is preserved up to three")
		var snapshot := GameSession._capture()
		snapshot.story.guests = {"stick":{"completed":5,"heard":{},"pending":{},"known":true,"content_revision":"stick-v0.3",
			"archive":[{"key":"legacy","text":"以前听过的话","speaker":"guest"}],"activity_unlocks":{}}}
		snapshot.active = {"guest_id":"stick","episode_id":"stick_05","node_id":"start","phase":"story","speech":"旧台词","idle_index":-1,"history":[],"content_revision":"stick-v0.3","taste_event_id":""}
		var file := FileAccess.open(GameSession.save_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(snapshot))
		file.close()
	print("RELEASE DEMO: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
