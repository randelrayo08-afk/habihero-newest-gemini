extends "res://shared_nav.gd"
# Shop Handler - Manages shop items, purchasing, and horizontal scrolling
# Now with REAL-TIME coin balance updates!

var _current_user_id: String = ""
var _user_coins: int = 0
var _profile_sync: Node  # Real-time profile syncer

# Shop items data with recovery amount and coin price
var _shop_items: Array = [
	{"id": "recovery_potion_20", "name": "20-Point Recovery Potion", "price": 20, "recovery_points": 20, "icon": "💊", "description": "Recover 20 points."},
	{"id": "recovery_potion_40", "name": "40-Point Recovery Potion", "price": 40, "recovery_points": 40, "icon": "💊", "description": "Recover 40 points."},
	{"id": "recovery_potion_60", "name": "60-Point Recovery Potion", "price": 60, "recovery_points": 60, "icon": "💊", "description": "Recover 60 points."},
	{"id": "recovery_potion_80", "name": "80-Point Recovery Potion", "price": 80, "recovery_points": 80, "icon": "💊", "description": "Recover 80 points."},
	{"id": "recovery_potion_100", "name": "100-Point Recovery Potion", "price": 100, "recovery_points": 100, "icon": "💊", "description": "Recover 100 points."},
	{"id": "recovery_potion_200", "name": "200-Point Recovery Potion", "price": 200, "recovery_points": 200, "icon": "💊", "description": "Recover 200 points."},
	{"id": "recovery_potion_500", "name": "500-Point Recovery Potion", "price": 500, "recovery_points": 500, "icon": "💊", "description": "Recover 500 points."},
]

var _scroll_container: Control
var _items_container: HBoxContainer
var _scroll_index: int = 0

var _left_button: Button
var _right_button: Button
var _coins_label: Label
var _buy_buttons: Array[Button] = []
var _confirm_dialog: ConfirmationDialog
var _pending_purchase_item: Dictionary = {}
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_timer: Timer
var _authored_scroll_ready: bool = false
var _carousel_cards: Array[Control] = []
var _carousel_index: int = 0
var _carousel_interacted: bool = false

func _ready() -> void:
	super._ready()
	_ensure_navigation_layer()
	_wire_shop_navigation()
	_auth_manager = get_tree().root.get_node_or_null("FirebaseAuthManager")
	
	# Get UI elements
	_scroll_container = get_node_or_null("Panel4/Panel6/Panel")
	_items_container = get_node_or_null("Panel4/Panel6/Panel/HBoxContainer")
	_left_button = get_node_or_null("Panel4/Panel6/LeftButton")
	_right_button = get_node_or_null("Panel4/Panel6/RightButton")
	_coins_label = get_node_or_null("Button/Panel/Label")
	
	# Connect buttons
	if _left_button:
		_left_button.pressed.connect(_on_scroll_left)
	if _right_button:
		_right_button.pressed.connect(_on_scroll_right)
	
	# Setup real-time profile sync
	_profile_sync = _resolve_or_create_profile_sync()
	if _profile_sync:
		_profile_sync.set_profile_update_callback(Callable(self, "_on_profile_updated_realtime"))
	
	# Load user and initialize shop
	_load_user_data()
	_initialize_shop()

	# Create confirmation dialog for purchases
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.name = "PurchaseConfirm"
	_confirm_dialog.get_ok_button().text = "Confirm"
	_confirm_dialog.get_cancel_button().text = "Cancel"
	_confirm_dialog.connect("confirmed", Callable(self, "_on_confirmed_purchase"))
	add_child(_confirm_dialog)

	# Create a simple toast panel for on-screen messages
	_toast_panel = PanelContainer.new()
	_toast_panel.name = "ToastPanel"
	_toast_panel.visible = false
	_toast_panel.anchor_left = 0.25
	_toast_panel.anchor_right = 0.75
	_toast_panel.anchor_top = 0.02
	_toast_panel.anchor_bottom = 0.10
	_toast_panel.offset_left = 0
	_toast_panel.offset_top = 0
	_toast_panel.offset_right = 0
	_toast_panel.offset_bottom = 0
	var toast_style := StyleBoxFlat.new()
	toast_style.bg_color = Color(0, 0, 0, 0.7)
	toast_style.corner_radius_top_left = 8
	toast_style.corner_radius_top_right = 8
	toast_style.corner_radius_bottom_left = 8
	toast_style.corner_radius_bottom_right = 8
	_toast_panel.add_theme_stylebox_override("panel", toast_style)
	_toast_label = Label.new()
	_toast_label.name = "ToastLabel"
	_toast_label.text = ""
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.add_theme_color_override("font_color", Color(1,1,1,1))
	_toast_label.add_theme_font_size_override("font_size", 14)
	_toast_panel.add_child(_toast_label)
	add_child(_toast_panel)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.wait_time = 2.5
	_toast_timer.connect("timeout", Callable(self, "_hide_toast"))
	add_child(_toast_timer)

func _ensure_navigation_layer() -> void:
	var navigation_panel: Control = get_node_or_null("Panel2") as Control
	if navigation_panel == null:
		return
	navigation_panel.z_index = 1000
	navigation_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	navigation_panel.move_to_front()
	for child in navigation_panel.get_children():
		if child is Button:
			(child as Button).z_index = 1001

func _wire_shop_navigation() -> void:
	for button_key in ["homebut", "progbut", "jourbut", "shopbut", "guibot"]:
		var button: Button = get_node_or_null("Panel2/" + button_key) as Button
		if button == null:
			continue
		var callback: Callable = Callable(self, "_switch_to_scene").bind(NAV_MAP[{
			"homebut": "home",
			"progbut": "progress",
			"jourbut": "journal",
			"shopbut": "shop",
			"guibot": "guidance"
		}[button_key]])
		if not button.pressed.is_connected(callback):
			button.pressed.connect(callback)

func _load_user_data() -> void:
	"""Load current user ID and coin balance"""
	if _auth_manager and _auth_manager.has_method("get_current_user_id"):
		_current_user_id = str(_auth_manager.call("get_current_user_id"))
		_load_coin_balance()

func _resolve_or_create_profile_sync() -> Node:
	"""Get or create profile sync manager"""
	if get_tree() != null and get_tree().root != null:
		var existing_sync: Node = get_tree().root.get_node_or_null("FirebaseProfileSync")
		if existing_sync != null:
			return existing_sync
	# Create new sync if doesn't exist
	var new_sync = load("res://firebase_profile_sync.gd").new()
	get_tree().root.add_child.call_deferred(new_sync)
	new_sync.name = "FirebaseProfileSync"
	return new_sync

func _on_profile_updated_realtime(profile_data: Dictionary) -> void:
	"""Handle real-time profile updates"""
	var new_coins = int(profile_data.get("coin_balance", profile_data.get("coins", _user_coins)))
	if new_coins != _user_coins:
		print("Real-Time: Coins updated from %d to %d" % [_user_coins, new_coins])
		_user_coins = new_coins
		_update_coins_display()


func _load_coin_balance() -> void:
	"""Load user's coin balance from database"""
	if _auth_manager and _auth_manager.has_method("load_coin_balance"):
		_auth_manager.call("load_coin_balance", _current_user_id, func(ok: bool, balance: Variant):
			if not is_instance_valid(self):
				return
			if ok:
				_user_coins = int(balance) if balance is int else 0
				_update_coins_display()
		)

func _initialize_shop() -> void:
	"""Populate the authored shop panels from Shop.tscn."""
	_carousel_index = 0
	_scroll_index = 0
	_prepare_authored_scroll_layout()
	_buy_buttons.clear()
	_collect_buy_buttons(self)
	for item_index in range(min(_shop_items.size(), _buy_buttons.size())):
		_populate_existing_item_panel(_buy_buttons[item_index], _shop_items[item_index])
	_add_carousel_loop_cards()
	call_deferred("_center_initial_carousel")
	_update_scroll_buttons()

func _center_initial_carousel() -> void:
	for attempt in range(8):
		await get_tree().process_frame
		if _carousel_interacted or not is_instance_valid(self) or _items_container == null or _scroll_container == null:
			return
		_items_container.queue_sort()
		_focus_carousel_card(0, false)

func _prepare_authored_scroll_layout() -> void:
	if _authored_scroll_ready:
		return
	var card_host: Panel = get_node_or_null("Panel4/Panel6") as Panel
	var panel4: Panel = get_node_or_null("Panel4") as Panel
	if card_host == null or panel4 == null:
		return
	var authored_buttons: Array[Button] = []
	_collect_authored_buy_buttons(card_host, authored_buttons)
	if authored_buttons.is_empty():
		return

	var first_root: Node = authored_buttons[0].get_parent()
	var first_card: Panel = first_root.get_node_or_null("Panel") as Panel
	if first_card == null:
		return

	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "AuthoredShopScroll"
	_scroll_container.position = Vector2(0, -260)
	_scroll_container.size = Vector2(575, 540)
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel4.add_child(_scroll_container)
	_items_container = HBoxContainer.new()
	_items_container.name = "AuthoredShopCards"
	_items_container.add_theme_constant_override("separation", 20)
	_items_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scroll_container.add_child(_items_container)

	_carousel_cards.clear()
	var first_button: Button = authored_buttons[0]
	first_root.reparent(_items_container, false)
	first_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	first_root.position = Vector2.ZERO
	first_root.size = Vector2(223, 363)
	first_root.custom_minimum_size = Vector2(223, 363)
	first_root.pivot_offset = first_root.size / 2.0
	_carousel_cards.append(first_root as Control)
	first_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	first_card.position = Vector2(8, 15)
	first_card.size = Vector2(208, 334)
	first_card.custom_minimum_size = Vector2(208, 334)
	first_button.reparent(first_card, false)
	_position_buy_button(first_button, first_card)

	for button_index in range(1, authored_buttons.size()):
		var authored_root: Node = authored_buttons[button_index].get_parent()
		var authored_card: Panel = authored_root.get_node_or_null("Panel") as Panel
		if authored_card == null:
			continue
		if authored_root.get_parent() != _items_container:
			authored_root.reparent(_items_container, false)
		if authored_root is Control:
			(authored_root as Control).set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			(authored_root as Control).position = Vector2.ZERO
			(authored_root as Control).size = Vector2(223, 363)
			(authored_root as Control).custom_minimum_size = Vector2(223, 363)
			(authored_root as Control).pivot_offset = (authored_root as Control).size / 2.0
		authored_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		authored_card.position = Vector2(8, 15)
		authored_card.size = Vector2(208, 334)
		authored_card.custom_minimum_size = Vector2(208, 334)
		authored_buttons[button_index].reparent(authored_card, false)
		_position_buy_button(authored_buttons[button_index], authored_card)
		_carousel_cards.append(authored_root as Control)

	_carousel_cards.clear()
	for row_child in _items_container.get_children():
		if row_child is Control:
			_carousel_cards.append(row_child as Control)

	if _left_button != null:
		_left_button.reparent(panel4, true)
		_left_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_left_button.position = Vector2(125, 100)
		_left_button.size = Vector2(64, 52)
		_left_button.custom_minimum_size = Vector2(64, 52)
		_left_button.add_theme_font_size_override("font_size", 24)
	if _right_button != null:
		_right_button.reparent(panel4, true)
		_right_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_right_button.position = Vector2(335, 100)
		_right_button.size = Vector2(64, 52)
		_right_button.custom_minimum_size = Vector2(64, 52)
		_right_button.add_theme_font_size_override("font_size", 24)
	_authored_scroll_ready = true

func _add_carousel_loop_cards() -> void:
	if _items_container == null or _carousel_cards.size() < 2:
		return
	var last_clone: Control = _carousel_cards[_carousel_cards.size() - 1].duplicate() as Control
	var first_clone: Control = _carousel_cards[0].duplicate() as Control
	if last_clone == null or first_clone == null:
		return
	last_clone.name = "CarouselCloneLast"
	first_clone.name = "CarouselCloneFirst"
	var leading_spacer := Control.new()
	leading_spacer.name = "CarouselLeadingSpacer"
	leading_spacer.custom_minimum_size = Vector2(0, 1)
	_items_container.add_child(leading_spacer)
	_items_container.move_child(leading_spacer, 0)
	_items_container.add_child(last_clone)
	_items_container.move_child(last_clone, 0)
	_items_container.add_child(first_clone)
	var trailing_spacer := Control.new()
	trailing_spacer.name = "CarouselTrailingSpacer"
	trailing_spacer.custom_minimum_size = Vector2(0, 1)
	_items_container.add_child(trailing_spacer)
	last_clone.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	first_clone.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	last_clone.custom_minimum_size = Vector2(223, 363)
	first_clone.custom_minimum_size = Vector2(223, 363)
	_connect_clone_buy_button(last_clone, _shop_items[_shop_items.size() - 1])
	_connect_clone_buy_button(first_clone, _shop_items[0])

func _connect_clone_buy_button(card: Control, item: Dictionary) -> void:
	var clone_buttons: Array[Button] = []
	_collect_authored_buy_buttons(card, clone_buttons)
	if clone_buttons.is_empty():
		return
	var purchase_callback := Callable(self, "_on_buy_pressed").bind(item)
	if not clone_buttons[0].pressed.is_connected(purchase_callback):
		clone_buttons[0].pressed.connect(purchase_callback)

func _collect_authored_buy_buttons(node: Node, target: Array[Button]) -> void:
	if node is Button and (node as Button).text == "BUY":
		target.append(node as Button)
		return
	for child in node.get_children():
		_collect_authored_buy_buttons(child, target)

func _collect_buy_buttons(node: Node) -> void:
	if node is Button and (node as Button).text == "BUY":
		_buy_buttons.append(node as Button)
		return
	for child in node.get_children():
		_collect_buy_buttons(child)

func _position_buy_button(buy_button: Button, card_panel: Panel) -> void:
	buy_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	buy_button.size = Vector2(85, 32)
	buy_button.position = Vector2((card_panel.size.x - buy_button.size.x) / 2.0, card_panel.size.y - buy_button.size.y - 10.0)

func _populate_existing_item_panel(buy_button: Button, item: Dictionary) -> void:
	var card_root: Node = buy_button.get_parent()
	var card_panel: Panel = card_root as Panel
	if card_panel == null:
		card_panel = card_root.get_node_or_null("Panel") as Panel
	if card_panel == null:
		return
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color.WHITE
	card_style.border_width_left = 2
	card_style.border_width_top = 2
	card_style.border_width_right = 2
	card_style.border_width_bottom = 2
	card_style.border_color = Color.BLACK
	card_style.corner_radius_top_left = 45
	card_style.corner_radius_top_right = 45
	card_style.corner_radius_bottom_left = 45
	card_style.corner_radius_bottom_right = 45
	card_panel.add_theme_stylebox_override("panel", card_style)
	for child in card_panel.get_children():
		if child != buy_button:
			child.queue_free()
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8.0
	vbox.offset_top = 10.0
	vbox.offset_right = -8.0
	vbox.offset_bottom = -45.0
	vbox.add_theme_constant_override("separation", 6)
	card_panel.add_child(vbox)

	var icon_label := Label.new()
	icon_label.text = str(item.get("icon", ""))
	icon_label.add_theme_font_size_override("font_size", 42)
	icon_label.add_theme_color_override("font_color", Color.BLACK)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(icon_label)

	var name_label := Label.new()
	name_label.text = str(item.get("name", "Item"))
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color.BLACK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = str(item.get("description", ""))
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color.BLACK)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)

	var price_label := Label.new()
	price_label.text = "%d Coins" % int(item.get("price", 0))
	price_label.add_theme_font_size_override("font_size", 14)
	price_label.add_theme_color_override("font_color", Color.BLACK)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(price_label)

	var purchase_callback := Callable(self, "_on_buy_pressed").bind(item)
	if not buy_button.pressed.is_connected(purchase_callback):
		buy_button.pressed.connect(purchase_callback)

func _on_buy_pressed(item: Dictionary) -> void:
	"""Handle buy button pressed"""
	# Validate purchase before showing confirmation
	if not _validate_purchase(item):
		_show_message("Cannot complete purchase!")
		return
	
	_pending_purchase_item = item.duplicate(true)
	var price = int(item["price"])
	var confirm_text = "Are you sure you want to buy %s for %d coins?\n\nYour balance: %d coins" % [item["name"], price, _user_coins]
	_confirm_dialog.dialog_text = confirm_text
	_confirm_dialog.get_ok_button().disabled = false
	_confirm_dialog.popup_centered_clamped()

func _validate_purchase(item: Dictionary) -> bool:
	"""Validate if purchase can be made"""
	if item.size() == 0:
		push_warning("ShopHandler: Invalid item data.")
		_show_message("Invalid item!")
		return false
	
	var price = int(item.get("price", 0))
	if price <= 0:
		push_warning("ShopHandler: Invalid price %d" % price)
		_show_message("Invalid price!")
		return false
	
	if _user_coins < price:
		_show_message("Not enough coins! Need %d, have %d" % [price, _user_coins])
		return false
	
	return true

func _save_purchase() -> void:
	"""Save purchase to database"""
	# This is now handled in _on_buy_pressed
	pass

func _on_confirmed_purchase() -> void:
	if _pending_purchase_item.size() == 0:
		return
	var item: Dictionary = _pending_purchase_item
	var price: int = int(item.get("price", 0))

	if _user_coins < price:
		_pending_purchase_item = {}
		_show_message("Not enough coins! Need %d, have %d" % [price, _user_coins])
		return

	var new_balance = _user_coins - price
	# Save to database
	if _auth_manager and _auth_manager.has_method("save_coin_balance"):
		_auth_manager.call("save_coin_balance", _current_user_id, new_balance, func(ok: bool):
			if not is_instance_valid(self):
				return
			if ok:
				_user_coins = new_balance
				_update_coins_display()
				_show_message("Purchased %s! ✨" % item["name"])
				_trigger_game_sound("potion_buy")
				print("Purchased: %s for %d coins. New balance: %d" % [item["name"], price, new_balance])
			else:
				print("Failed to save purchase")
				_show_message("Purchase failed! Try again.")
			_pending_purchase_item = {}
		)
	else:
		# Fallback if method doesn't exist
		_user_coins = new_balance
		_update_coins_display()
		_show_message("Purchased %s! ✨" % item["name"])
		_trigger_game_sound("potion_buy")
		print("Purchased: %s for %d coins (offline)" % [item["name"], price])
		_pending_purchase_item = {}

func _trigger_game_sound(sound_name: String) -> void:
	if get_tree() == null or get_tree().root == null:
		return
	var audio_node: Node = get_tree().root.get_node_or_null("AdventureAudio")
	if audio_node == null:
		return
	match sound_name:
		"potion_buy":
			if audio_node.has_method("play_potion_buy"):
				audio_node.call("play_potion_buy")
		_:
			pass

func _update_coins_display() -> void:
	"""Update coins label UI"""
	if _coins_label:
		_coins_label.text = "💰 Coins: %d" % _user_coins

func _on_scroll_left() -> void:
	"""Move to the previous panel using the left button."""
	_carousel_interacted = true
	if not _carousel_cards.is_empty():
		var wraps_to_end: bool = _carousel_index == 0
		_carousel_index = _carousel_cards.size() - 1 if wraps_to_end else _carousel_index - 1
		_scroll_index = _carousel_index
		_focus_carousel_card(_carousel_index, true, 0 if wraps_to_end else -1)
		_update_scroll_buttons()

func _on_scroll_right() -> void:
	"""Move to the next panel using the right button."""
	_carousel_interacted = true
	if not _carousel_cards.is_empty():
		var wraps_to_start: bool = _carousel_index == _carousel_cards.size() - 1
		_carousel_index = 0 if wraps_to_start else _carousel_index + 1
		_scroll_index = _carousel_index
		_focus_carousel_card(_carousel_index, true, _carousel_cards.size() + 1 if wraps_to_start else -1)
		_update_scroll_buttons()

func _animate_scroll() -> void:
	"""Animate horizontal scroll with smoother, centered card motion."""
	if not _scroll_container or not _items_container or not _scroll_container is ScrollContainer:
		return
	
	var item_width = 223.0
	var item_spacing = 20.0
	var target_scroll = float(_scroll_index) * (item_width + item_spacing) + 0.0 + item_width / 2.0 - _scroll_container.size.x / 2.0
	var max_scroll: float = maxf(0.0, _items_container.size.x - _scroll_container.size.x)
	target_scroll = clampf(target_scroll, 0.0, max_scroll)
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_scroll_container, "scroll_horizontal", target_scroll, 0.45)
	_apply_carousel_card_state(_carousel_index)

func _apply_carousel_card_state(_selected_index: int) -> void:
	"""Apply card state - hover effects removed"""
	if _carousel_cards.is_empty():
		return
	# No hover/scale effects - cards stay at neutral state

func _focus_carousel_card(card_index: int, animate: bool = true, row_index_override: int = -1) -> void:
	if _scroll_container == null or _items_container == null or _carousel_cards.is_empty():
		return
	_carousel_index = clampi(card_index, 0, _carousel_cards.size() - 1)
	var viewport_width: float = _scroll_container.size.x
	var card_width: float = 223.0
	var card_spacing: float = 20.0
	var row_index: int = _carousel_index + 1 if row_index_override < 0 else row_index_override
	var target_scroll: float = float(row_index) * (card_width + card_spacing) + 0.0 + card_width / 2.0 - viewport_width / 2.0
	var max_scroll: float = maxf(0.0, _items_container.size.x - viewport_width)
	target_scroll = clampf(target_scroll, 0.0, max_scroll)
	if animate:
		var scroll_tween := create_tween()
		scroll_tween.set_trans(Tween.TRANS_SINE)
		scroll_tween.set_ease(Tween.EASE_OUT)
		scroll_tween.tween_property(_scroll_container, "scroll_horizontal", target_scroll, 0.45)
		scroll_tween.tween_callback(Callable(self, "_apply_carousel_card_state").bind(_carousel_index))
		if row_index_override >= 0:
			scroll_tween.tween_callback(Callable(self, "_reset_carousel_scroll").bind(_carousel_index))
	else:
		_scroll_container.scroll_horizontal = int(target_scroll)
		_apply_carousel_card_state(_carousel_index)

func _reset_carousel_scroll(card_index: int) -> void:
	if _scroll_container == null:
		return
	var normal_target: float = float(card_index + 1) * 243.0 + 0.0 + 111.5 - _scroll_container.size.x / 2.0
	_scroll_container.scroll_horizontal = int(clampf(normal_target, 0.0, maxf(0.0, _items_container.size.x - _scroll_container.size.x)))

func _update_scroll_buttons() -> void:
	"""Enable/disable scroll buttons based on position"""
	if _left_button:
		_left_button.disabled = false
	
	if _right_button:
		_right_button.disabled = false

func _show_message(message: String) -> void:
	"""Show a temporary message to the user"""
	print("Message: %s" % message)
	if _toast_panel != null and _toast_label != null and _toast_timer != null:
		_toast_label.text = message
		_toast_panel.visible = true
		# restart timer
		_toast_timer.stop()
		_toast_timer.start()
	else:
		# fallback
		print(message)
	# For now we also print to console

func _hide_toast() -> void:
	if _toast_panel != null:
		_toast_panel.visible = false
	if _toast_label != null:
		_toast_label.text = ""
