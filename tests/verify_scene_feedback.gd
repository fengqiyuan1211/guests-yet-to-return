extends "res://tests/verify_workbench_drag.gd"

func run() -> void:
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	var ui: Node=SaloonAudio.ui
	ui.focused=true
	var button:=Button.new()
	button.size=Vector2(120,40)
	button.position=Vector2(1150,800)
	add_child(button)
	await settle()
	var before: int=ui.played
	click(button)
	check(ui.played==before+1 and ui.last_cue=="click","native button plays one shared click")
	button.disabled=true
	await get_tree().create_timer(.06).timeout
	click(button)
	check(ui.played==before+1,"disabled button is silent")
	button.queue_free()
	var hall: String=SaloonAudio.active_path
	Navigation.go_to(&"research")
	await settle()
	check(SaloonAudio.active_path==SaloonAudio.SCENE_TRACKS.research,"research has own music")
	Navigation.go_to(&"shop")
	await settle()
	var shop: Control=home.active_page
	check(SaloonAudio.active_path==SaloonAudio.SCENE_TRACKS.shop,"shop has own music")
	check(SaloonAudio.scene_owners.size()==1,"disposed research releases ownership")
	var shop_before: int=ui.played
	var product: Button=shop.slot_buttons[0]
	pointer(product.get_global_transform_with_canvas()*Vector2(120,190),true)
	pointer(product.get_global_transform_with_canvas()*Vector2(120,190),false)
	check(ui.played==shop_before+1 and ui.last_cue=="bottle","product selection has material sound without duplicate generic click")
	# Select valid in-category products through the actual category view.
	shop._set_category("配料")
	shop._select_item("sku_mint_leaf")
	check(ui.last_cue=="leaf","herb category resolves its material")
	shop._select_item("sku_white_cane_sugar")
	check(ui.last_cue=="grain","sugar selection uses granular cue")
	shop._set_category("装饰品")
	var fruit_id: String=shop.products[0].id
	shop._select_item(fruit_id)
	check(ui.last_cue=="fruit","garnish selection uses soft fruit cue")
	SlotWallet.balance=300000
	check(SlotWallet.persist(),"private purchase fixture wallet")
	shop._update_receipt()
	var stock: Dictionary=Supplies.get_state(fruit_id).duplicate(true)
	var cash: int=SlotWallet.balance
	var price: int=shop._unit_price(shop._selected_item())
	before=ui.played
	click(shop.buy_button)
	check(ui.played==before+1 and ui.last_cue=="purchase-fruit","successful transaction has one material and coin cue")
	check(SlotWallet.balance==cash-price and Supplies.get_state(fruit_id)!=stock,"purchase audio follows actual debit and stock write")
	# Failed persistence must not announce purchase success.
	var path: String=Supplies.save_path
	Supplies.save_path=path+"/blocked.json"
	before=ui.played
	shop._purchase()
	check(ui.last_cue=="click" and ui.played==before+1,"failed purchase never plays success cue")
	check(SlotWallet.balance==cash-price,"failed purchase keeps wallet")
	Supplies.save_path=path
	Navigation.go_to(&"home")
	await settle()
	check(SaloonAudio.active_path==hall and SaloonAudio.scene_owners.is_empty(),"return resumes hall track and releases scene owners")
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	check(SaloonAudio.active_path==SaloonAudio.WORKBENCH_TRACK,"workbench still has own music")
	bench._open_storage("shop")
	await settle()
	check(SaloonAudio.active_path==SaloonAudio.SCENE_TRACKS.shop and SaloonAudio.scene_owners.size()==2,"shop overlay overrides workbench music")
	bench.external_page.close_requested.emit()
	await settle()
	check(SaloonAudio.active_path==SaloonAudio.WORKBENCH_TRACK and SaloonAudio.scene_owners.size()==1,"closing shop restores workbench music")
	await get_tree().create_timer(3.7).timeout
	var playing:=0
	for player in SaloonAudio.players:
		if player.playing: playing+=1
	check(playing==1,"crossfade stops outgoing music deck")
	TimeManager.minutes_since_midnight=TimeManager.OPEN_MINUTE
	await settle()
	check(SaloonAudio.active_path==SaloonAudio.WORKBENCH_TRACK,"clock change does not replace active scene music")
	Navigation.go_to(&"home")
	await settle()
	check(SaloonAudio.active_path==SaloonAudio.NIGHT_TRACKS[SaloonAudio.night_index],"exit chooses new night hall playlist after clock change")
	SaloonAudio.set_volume("SFX",0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),"shared mute covers UI and workbench")
	for voice in ui.voices: check(voice.bus==&"SFX","UI voice uses SFX bus")
	SaloonAudio.set_volume("SFX",80)
	ui._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	before=ui.played
	ui.play("bottle")
	check(ui.played==before,"focus loss suppresses new UI sounds")
	for voice in ui.voices: check(not voice.playing,"focus loss silences active sounds")
	ui._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	for context in SaloonAudio.SCENE_TRACKS:
		var clip: AudioStream=SaloonAudio._stream_for(SaloonAudio.SCENE_TRACKS[context])
		check(clip!=null and clip.get_length()>60,"scene music asset decodes: "+context)
	await capture("feedback-muddler-audio")
	Navigation.go_to(&"settings")
	await settle()
	await capture("feedback-music-credits")
	print("SCENE FEEDBACK: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
