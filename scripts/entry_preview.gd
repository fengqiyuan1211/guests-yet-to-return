extends Control
## Honest entry previews, replaced by real module scenes as features are built.
signal close_requested
var route_data: Dictionary
var selected_tab := 0

func configure(data: Dictionary) -> void:
	route_data = data
	%PageTitle.text = data.title
	%PageSubtitle.text = data.subtitle
	%FeatureList.text = data.next
	for child in %Tabs.get_children():
		child.queue_free()
	for index in range(data.tabs.size()):
		var button := Button.new()
		button.text = data.tabs[index]
		button.custom_minimum_size = Vector2(0, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.pressed.connect(_select_tab.bind(index))
		%Tabs.add_child(button)
	_select_tab(0)

func _ready() -> void:
	%CloseButton.pressed.connect(func(): close_requested.emit())
	%ReturnButton.pressed.connect(func(): close_requested.emit())
	%Backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			close_requested.emit()
	)
	%CloseButton.grab_focus()

func _select_tab(index: int) -> void:
	selected_tab = index
	%Description.text = route_data.notes[index]
	for i in range(%Tabs.get_child_count()):
		var button := %Tabs.get_child(i) as Button
		button.set_pressed_no_signal(i == index)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
