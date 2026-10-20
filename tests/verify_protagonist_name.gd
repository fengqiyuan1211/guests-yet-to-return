extends "res://tests/verify_opening.gd"

func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await get_tree().create_timer(.5).timeout
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute("/tmp/protagonist-name-preview")
	get_viewport().get_texture().get_image().save_png("/tmp/protagonist-name-preview/"+label+".png")

func run() -> void:
	if not GameSession.save_path.begins_with("/tmp/"): get_tree().quit(2); return
	if "--name-resume" in OS.get_cmdline_user_args():
		check(OpeningFlow.protagonist_name()=="林 归舟","name survives a fresh process")
		check(OpeningFlow.state.departure.node=="find_you" and OpeningFlow.state.departure.signed,"name and signed cursor restore together")
		check(OpeningFlow.protagonist_speaker("我 · 心声")=="林 归舟 · 心声","inner voice uses the protagonist name")
		check(OpeningFlow.protagonist_speaker("老管家")=="老管家","other speakers remain unchanged")
		var official:=FileAccess.get_file_as_string(OpeningFlow.save_path)
		var path:=OpeningFlow.save_path
		check(OpeningFlow.begin_replay() and OpeningFlow.protagonist_name()=="林 归舟","replay starts with official name")
		check(OpeningFlow.begin_tutorial() and OpeningFlow.finish_tutorial(true) and OpeningFlow.begin_departure(),"prepare replay signature")
		OpeningFlow.update_departure({"node":"sign_receipt"})
		check(OpeningFlow.sign_receipt("回看试名"),"replay accepts a temporary signature")
		check(FileAccess.get_file_as_string(path)==official,"replay never overwrites official name or cursor")
		get_tree().current_scene=null # Keep the test runner alive across the real transition.
		OpeningFlow.return_to_title()
		await settle_opening_transition()
		check(OpeningFlow.protagonist_name()=="林 归舟","leaving replay restores official identity")
	else:
		check(OpeningFlow.valid(OpeningFlow.fresh()),"old saves without names stay compatible")
		check(OpeningFlow.begin_story() and OpeningFlow.begin_tutorial() and OpeningFlow.finish_tutorial(true),"prepare signature scene")
		await show_scene("res://scenes/opening_departure.tscn")
		OpeningFlow.update_departure({"node":"sign_receipt"}); page._render()
		page.dialogue.visible_characters=-1
		await settle()
		await shot("01-name-entry")
		var before:=OpeningFlow.state.duplicate(true)
		await pointer_click(page.signature_button)
		check(OpeningFlow.state==before and page.name_hint.text.contains("请先"),"empty name cannot sign or advance")
		check(not OpeningFlow.sign_receipt("   "),"whitespace-only name rejected by service")
		check(not OpeningFlow.sign_receipt("名字".repeat(9)),"overlong name rejected by service")
		check(not OpeningFlow.sign_receipt("林\n舟"),"embedded newline rejected")
		check(not OpeningFlow.sign_receipt("\u200b"),"invisible-only name rejected")
		check(page.name_edit.max_length==16 and not page._can_auto_advance(),"editor is bounded and autoplay pauses")
		page.name_edit.text="林"; page.name_edit.grab_focus(); page.name_edit.caret_column=1
		for character in [[KEY_SPACE,32],[KEY_H,104],[KEY_A,97]]:
			for down in [true,false]:
				var event:=InputEventKey.new()
				event.keycode=character[0]; event.physical_keycode=character[0]
				event.unicode=character[1]; event.pressed=down
				get_viewport().push_input(event,true)
			await settle()
		check(page.name_edit.text=="林 ha","real keyboard characters reach the focused name field")
		check(OpeningFlow.state==before and not page.fast_forward.held and not is_instance_valid(page.history_panel) and not page.autoplay.enabled,"typing Space/H/A cannot sign, fast-forward or open history")
		page.name_edit.text="  林 归舟  "
		page.name_edit.text_changed.emit(page.name_edit.text)
		var path:=OpeningFlow.save_path
		OpeningFlow.save_path+="/missing"
		await pointer_click(page.signature_button)
		check(OpeningFlow.state==before and not page.busy and page.name_edit.editable,"write failure preserves name draft and unsigned cursor")
		OpeningFlow.save_path=path
		page.status.text="输入时空格与字母只用于填写 · 点击按钮确认"
		page.clock=page.dialogue.text.length()
		await shot("02-name-filled")
		await pointer_click(page.signature_button)
		check(OpeningFlow.state.departure.signed and OpeningFlow.protagonist_name()=="林 归舟","mouse confirmation trims edges and persists name")
		page._advance()
		check(OpeningFlow.state.departure.node=="find_you","double click cannot skip the next scene")
		check(OpeningFlow.sign_receipt("林 归舟"),"same signature retry is idempotent")
		check(not OpeningFlow.sign_receipt("其他名字") and OpeningFlow.protagonist_name()=="林 归舟","signed receipt cannot silently rename protagonist")
		await shot("03-signed")
		while page.busy: await get_tree().process_frame
		check(OpeningFlow.valid(JSON.parse_string(FileAccess.get_file_as_string(path))),"persisted identity remains valid")
	print("PROTAGONIST NAME: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
