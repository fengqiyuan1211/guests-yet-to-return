extends Node
## Dedicated private-save preview; never switches the user's production profile.
func _ready() -> void:
	if not WorkbenchSession.save_path.begins_with("/tmp/guest-character-"):
		push_error("Use tools/play_character_activities.py for an isolated preview."); get_tree().quit(2); return
	var home:=preload("res://scenes/home.tscn").instantiate(); add_child(home)
	await get_tree().process_frame
	var route:="ada_watch_memory"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--activity="): route=arg.trim_prefix("--activity=")
	if route not in ["ada_watch_memory","milo_ferry","hank_lantern"]: route="ada_watch_memory"
	Navigation.journal_focus_guest=GuestActivities.config(route).guest_id
	Navigation.go_to(StringName(route))
