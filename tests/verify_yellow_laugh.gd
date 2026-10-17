extends Node
const Rules := preload("res://scripts/yellow_laugh_rules.gd")
var failures: Array[String] = []
var count := 0
var home: Control
func check(ok: bool, description: String) -> void:
	count += 1
	if not ok:
		failures.append(description)
		push_error(description)
func settle() -> void:
	for i in range(4): await get_tree().process_frame
func _ready() -> void:
	if "--laugh-test" not in OS.get_cmdline_user_args() or CustomerService.save_path.begins_with("user://"):
		get_tree().quit(2)
		return
	await settle()
	TimeManager.running = false
	var base := {"id":"test", "guest_id":"yellow_creature", "status":"settled", "craft":{"score":90.0}, "review":{"status":"scored", "satisfied":true}}
	check(Rules.eligible(base), "90 craft plus current preference satisfaction qualifies")
	for score in [89.9, 0.0, -1.0, 101.0, NAN, INF]:
		var low := base.duplicate(true)
		low.craft.score = score
		check(not Rules.eligible(low), "invalid/below-threshold craft excluded: %s" % score)
	for guest in ["stick", "ada", "milo", "hank"]:
		var other := base.duplicate(true); other.guest_id = guest
		check(not Rules.eligible(other), "other guest excluded: " + guest)
	var mismatch := base.duplicate(true); mismatch.review.satisfied = false
	check(not Rules.eligible(mismatch), "well-made but wrong taste does not laugh")
	mismatch.review.status = "rejected"; mismatch.review.satisfied = true
	check(not Rules.eligible(mismatch), "rejected cup does not laugh")
	var pending := base.duplicate(true); pending.status = "prepared"
	check(not Rules.eligible(pending), "payment must have settled")
	var free := base.duplicate(true); free.play_mode = "mixing"; free.free_settlement = {"matched":true}
	check(Rules.eligible(free), "matching free order qualifies")
	free.free_settlement.matched = false
	check(not Rules.eligible(free), "wrong free order does not laugh")
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	TimeManager.is_open = true
	TimeManager.minutes_since_midnight = 1200
	home._on_business_opened(1)
	home._on_time_changed(1,1200)
	var guests: Node = home.get_node("%GuestLayer")
	for i in range(guests.profiles.size()):
		if guests.profiles[i].id == "yellow_creature": guests.show_guest(i); break
	StoryDialogue.phase = "idle"
	var active: Dictionary = CustomerService.state.active
	var id := str(active.id) + ":laugh-test-cup"
	var demand: Dictionary = active.demand.duplicate(true)
	var actual := {"status":"complete", "attributes":demand.target.duplicate(true), "items":{}, "states":{}, "facts":{}}
	var review: Dictionary = CustomerService.Evaluation.evaluate(demand, actual, false, CustomerService.rules)
	check(review.get("satisfied", false), "real current yellow demand evaluates as satisfied")
	var record := {"id":id, "guest_id":"yellow_creature", "visit_id":active.id, "status":"prepared", "amount":42, "day":1,
		"actual":actual, "demand":demand, "review":review, "craft":{"score":95.0}, "previous_drink":{}, "recipe_id":"mojito",
		"feedback":{"round":1,"pending":false,"pending_reply":"","done":true,"story_resumed":false,"messages":[],
		"turn":{"text":"（它满意地推回空杯子。）","emotion":"pleased","replies":[],"end":true}}}
	active.delivery_id = id
	CustomerService.state.deliveries[id] = record
	check(CustomerService._valid_saved_state(CustomerService.state), "fixture and old records remain valid")
	var cash: int = SlotWallet.balance
	check(CustomerService._commit_delivery(id), "actual settlement enters feedback path")
	await settle()
	check(SlotWallet.balance == cash + 42, "payment occurs once before easter egg")
	check(guests.yellow_laugh_active() and not guests._art.visible, "home replaces guest with laugh art")
	check(guests._window.clip_contents, "reaction remains behind counter")
	check(home.get_node("%GuestSpeech").text.contains("笑弯了腰"), "laugh caption replaces feedback temporarily")
	check(home.get_node("%NextGuestButton").disabled and not home._can_advance_dialogue(), "cannot advance or send guest away during laugh")
	check(guests._laugh.player.bus == &"SFX" and absf(guests._laugh.player.stream.get_length() - 8.0) < .05, "eight second clip uses shared sound volume")
	var effect: Node = guests._laugh
	CustomerService.changed.emit()
	check(guests._laugh == effect, "background feedback updates do not restart animation")
	check(CustomerService._commit_delivery(id) and SlotWallet.balance == cash + 42, "repeat delivery does not repay")
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CustomerService.save_path))
	check(disk.deliveries[id].get(Rules.RECEIPT_KEY, false) and not Rules.eligible(disk.deliveries[id]), "playback claimed durably, reload cannot repeat")
	check(CustomerService._valid_saved_state(disk), "claimed flag compatible with save validator")
	SaloonAudio.set_volume("SFX",0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "settings mute covers laugh")
	SaloonAudio.set_volume("SFX",80)
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.65).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://laugh-in-game.png"))
	await get_tree().create_timer(8.1).timeout
	await settle()
	check(not guests.yellow_laugh_active() and guests._art.visible, "animation ends and original guest returns")
	check(home.get_node("%GuestSpeech").text == record.feedback.turn.text and not home.get_node("%NextGuestButton").disabled, "normal feedback and send-off resume")
	Navigation.go_to(&"settings")
	await settle()
	Navigation.go_to(&"home")
	await settle()
	check(not guests.yellow_laugh_active(), "return from settings does not replay")
	# A new receipt may trigger, but persistence failures must roll the marker back.
	record.erase(Rules.RECEIPT_KEY)
	var old_path: String = CustomerService.save_path
	CustomerService.save_path = old_path + "/missing/save.json"
	check(not CustomerService.claim_yellow_laugh(id) and not record.has(Rules.RECEIPT_KEY), "failed save rolls marker back")
	CustomerService.save_path = old_path
	home._render_dialogue()
	check(guests.yellow_laugh_active(), "unclaimed receipt can start after persistence recovers")
	var sound: AudioStreamPlayer = guests._laugh.player
	Navigation.go_to(&"settings")
	check(not sound.playing and not guests.yellow_laugh_active() and guests._art.visible, "leaving home stops voice and restores original art")
	await settle()
	Navigation.go_to(&"home")
	await settle()
	check(not guests.yellow_laugh_active(), "cancelled reaction never replays on return")
	record.erase(Rules.RECEIPT_KEY)
	home._render_dialogue()
	check(guests.yellow_laugh_active(), "fixture for guest cleanup starts")
	guests.clear_guest()
	check(not guests.yellow_laugh_active(), "guest cleanup disposes reaction")
	check(SlotWallet.balance == cash + 42 and CustomerService.state.deliveries.size() == 1, "reaction never changes money or review count")
	print("YELLOW LAUGH: %d checks, %d failures" % [count, failures.size()])
	print(failures)
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
