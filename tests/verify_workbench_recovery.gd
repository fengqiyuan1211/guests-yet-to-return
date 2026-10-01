extends Node
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _ready() -> void:
	if not WorkbenchSession.save_path.begins_with("/tmp/") or not GameSession.save_path.begins_with("/tmp/"):
		get_tree().quit(2)
		return
	var mode := "seed"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--workbench-mode="):
			mode=arg.trim_prefix("--workbench-mode=")
	if mode == "seed":
		check(WorkbenchSession.reset_game(),"reset")
		check(WorkbenchSession.set_table_materials(["gin","lime"]),"persist two resident bottles")
		check(WorkbenchSession.command("seed-start","","start"),"start")
		check(WorkbenchSession.command("seed-take","practice-1","withdraw",{"material":"gin","ml":18}),"take")
		check(WorkbenchSession.command("seed-transfer","practice-1","transfer",{"source":"jigger","vessel":"shaker"}),"transfer")
	elif mode == "resume":
		check(WorkbenchSession.state.session.id=="practice-1","same session across process")
		check(WorkbenchSession.state.table_materials==["gin","lime"],"same bottles across process")
		check(WorkbenchSession.state.stock.gin==582 and WorkbenchSession.state.session.vessels.shaker.contents.gin==18,"stock and contents across process")
		check(WorkbenchSession.command("seed-take","practice-1","withdraw",{"material":"gin","ml":18}),"old receipt reused")
		check(WorkbenchSession.state.stock.gin==582 and WorkbenchSession.state.session.vessels.jigger.contents.is_empty(),"no replay charge after restart")
		check(GameSession.restart_game(),"unified restart")
		check(WorkbenchSession.state.session.is_empty() and WorkbenchSession.state.stock.gin==600,"unified restart resets practice state")
	elif mode == "reset_check":
		check(WorkbenchSession.state.session.is_empty() and WorkbenchSession.state.stock.gin==600,"reset persists into next process")
	elif mode == "corrupt":
		var old_path := WorkbenchSession.save_path
		WorkbenchSession.save_path=old_path+".broken"
		var file := FileAccess.open(WorkbenchSession.save_path,FileAccess.WRITE)
		file.store_string('{"schema":1,"session":{}}')
		file.close()
		check(not WorkbenchSession.load_state() and not WorkbenchSession.writable,"corrupt state fails closed")
		check(not WorkbenchSession.command("no","","start"),"corrupt state refuses new writes")
		check(FileAccess.get_file_as_string(WorkbenchSession.save_path)=='{"schema":1,"session":{}}',"corrupt original preserved")
		WorkbenchSession.save_path=old_path
		check(WorkbenchSession.load_state(),"original still loads")
	print("WORKBENCH RECOVERY ",mode,": ","FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)
