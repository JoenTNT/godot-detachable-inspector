# Detachable Inspector - Copyright (C) 2026 | JoenTNT
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See <https://www.gnu.org/licenses/gpl-3.0.html> for the full license.

@tool
class_name JT_InspectorWindow
extends Window

# Events.
signal inspector_closed();
signal merge_drag_started();
signal detach_tab_requested();

# Runtime variable data.
var _tabs: TabContainer;
var _views: Dictionary[int, JT_InspectorTab] = {};
var _merge_handle: Button;
var _view_revision: int = 0;
var _placement_index: int = 0;
var _detach_button: Button;
var _pin_button: CheckButton;
var _history_manager: EditorUndoRedoManager;
var _history_id: int = EditorUndoRedoManager.INVALID_HISTORY;
var _scene_ref: WeakRef;
var _closing: bool = false;
var _tab_change_depth: int = 0;
var _validating_tabs: bool = false;
var _history_refresh_queued: bool = false;
var _positioned: bool = false;

#region Private Methods

func _init() -> void:
	visible = false
	force_native = true
	# Native always-on-top is incompatible with transient windows.
	transient = false
	always_on_top = true
	exclusive = false
	unresizable = false
	min_size = Vector2i(320, 360)
	size = Vector2i(480, 680)

func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free();
		return;
	
	var editor_scale: float = EditorInterface.get_editor_scale();
	min_size = Vector2i(Vector2(min_size) * editor_scale);
	size = Vector2i(Vector2(size) * editor_scale);
	theme = EditorInterface.get_editor_theme();
	var panel: PanelContainer = PanelContainer.new();
	panel.name = "InspectorPanel";
	add_child(panel);
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);
	var margin: MarginContainer = MarginContainer.new();
	margin.name = "InspectorMargin";
	var padding: int = roundi(8.0 * editor_scale);
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, padding);
	panel.add_child(margin);
	var layout: VBoxContainer = VBoxContainer.new();
	layout.name = "InspectorLayout";
	margin.add_child(layout);
	_build_toolbar(layout);
	_tabs = TabContainer.new();
	_tabs.name = "InspectorTabs";
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL;
	_tabs.clip_tabs = true;
	_tabs.drag_to_rearrange_enabled = true;
	layout.add_child(_tabs);
	_tabs.tab_changed.connect(_on_tab_changed);
	_tabs.active_tab_rearranged.connect(_on_tab_changed);
	_tabs.tab_button_pressed.connect(_on_tab_close_requested);
	close_requested.connect(close_inspector);

func _exit_tree() -> void:
	_closing = true
	_detach_scene()
	# Each tab also releases its own inspector/target in _exit_tree().
	_views.clear()

func _can_receive_from(source: Variant, empty_destination: bool) -> bool:
	if not empty_destination:
		return can_merge_with(source);
	return (
		not _closing and not is_queued_for_deletion() and is_inside_tree()
		and not visible and _views.is_empty() and _tab_change_depth == 0
		and source.is_merge_ready() and _scene_is_valid()
		and _get_scene_root() == source._get_scene_root()
		and _history_manager == source._history_manager and _history_id == source._history_id
	);

func _transfer_from(source: Variant, moving_tabs: Array[JT_InspectorTab], 
	empty_destination: bool = false) -> bool:
	if not _can_receive_from(source, empty_destination) or moving_tabs.is_empty():
		return false;
	if not empty_destination and not validate_context():
		return false;
	if not is_instance_valid(source) or not source.validate_context():
		return false;
	if not _can_receive_from(source, empty_destination):
		return false;
	var source_order: Array[JT_InspectorTab] = source._ordered_tabs()
	var source_active: JT_InspectorTab = source._get_active_tab()
	var previous_active: JT_InspectorTab = _get_active_tab()
	var prepared: Array[JT_InspectorTab] = []
	for itab: JT_InspectorTab in moving_tabs:
		if itab.get_parent() != source._tabs or not itab.begin_transfer():
			for prepared_tab: JT_InspectorTab in prepared: prepared_tab.end_transfer();
			return false;
		prepared.append(itab);
	_tab_change_depth += 1;
	source._tab_change_depth += 1;
	var transferred: bool = true;
	for itab: JT_InspectorTab in moving_tabs:
		source._unregister_tab(itab);
		_register_tab(itab);
		itab.reparent(_tabs, false);
		if (_closing or source._closing or itab.is_queued_for_deletion()
			or itab.get_parent() != _tabs
			or not _scene_is_valid() or not source._scene_is_valid()):
			transferred = false;
			break;
	
	if not transferred and not _closing and not source._closing:
		for itab: JT_InspectorTab in moving_tabs:
			if not is_instance_valid(itab) or itab.is_queued_for_deletion():
				continue;
			if _views.has(itab.get_instance_id()):
				_unregister_tab(itab);
				source._register_tab(itab);
				if itab.get_parent() != source._tabs:
					itab.reparent(source._tabs, false);
		for index: int in source_order.size():
			var itab: JT_InspectorTab = source_order[index];
			if is_instance_valid(itab) and itab.get_parent() == source._tabs:
				source._tabs.move_child(itab, index);
	for itab: JT_InspectorTab in prepared:
		if is_instance_valid(itab):
			itab.end_transfer();
	_tab_change_depth -= 1;
	source._tab_change_depth -= 1;
	if transferred and not _closing:
		for itab: JT_InspectorTab in moving_tabs:
			_update_tab_title(itab);
		_select_tab(source_active);
	else:
		_select_tab(previous_active);
		source._select_tab(source_active);
	source._sync_window_state();
	_sync_window_state();
	if transferred and not _closing: focus_inspector();
	return transferred and not _closing;

func _bind_scene(scroot: Node, history: EditorUndoRedoManager) -> bool:
	_scene_ref = weakref(scroot);
	if not _scene_is_valid(): return false;
	_history_manager = history;
	_history_id = _history_manager.get_object_history_id(scroot);
	if _history_id <= EditorUndoRedoManager.GLOBAL_HISTORY: return false;
	_history_manager.history_changed.connect(_queue_history_refresh);
	_history_manager.version_changed.connect(_queue_history_refresh);
	scroot.tree_exiting.connect(close_inspector);
	return true;

func _scene_is_valid() -> bool:
	var scroot: Node = _get_scene_root();
	return (is_instance_valid(scroot)
		and scroot.is_inside_tree()
		and not scroot.is_queued_for_deletion()
		and EditorInterface.get_edited_scene_root() == scroot);

func _on_tab_closed(view_id: int, itab: JT_InspectorTab) -> void:
	if _views.get(view_id) != itab: return;
	_tab_change_depth += 1;
	_unregister_tab(itab);
	if is_instance_valid(_tabs) and itab.get_parent() == _tabs:
		_tabs.remove_child(itab);
	_tab_change_depth -= 1;
	_sync_window_state();

func _on_tab_close_requested(tab_index: int) -> void:
	if _closing or _tab_change_depth > 0: return;
	if tab_index < 0 or tab_index >= _tabs.get_tab_count(): return;
	var itab: JT_InspectorTab = _tabs.get_tab_control(tab_index) as JT_InspectorTab;
	if is_instance_valid(itab):
		itab.close_inspector();

func _on_tab_changed(_tab_index: int) -> void:
	if _tab_change_depth == 0: _view_revision += 1;
	_sync_window_state();

func _register_tab(itab: JT_InspectorTab) -> void:
	var view_id: int = itab.get_instance_id();
	_views[view_id] = itab;
	_view_revision += 1;
	itab.inspector_closed.connect(_on_tab_closed.bind(view_id, itab));
	itab.target_title_changed.connect(_update_tab_title.bind(itab));

func _unregister_tab(itab: JT_InspectorTab) -> void:
	var view_id: int = itab.get_instance_id();
	_views.erase(view_id);
	_view_revision += 1;
	var close_callback: Callable = _on_tab_closed.bind(view_id, itab);
	if itab.inspector_closed.is_connected(close_callback):
		itab.inspector_closed.disconnect(close_callback);
	var title_callback: Callable = _update_tab_title.bind(itab);
	if itab.target_title_changed.is_connected(title_callback):
		itab.target_title_changed.disconnect(title_callback);

func _ordered_tabs() -> Array[JT_InspectorTab]:
	var result: Array[JT_InspectorTab] = [];
	for index: int in _tabs.get_tab_count():
		result.append(_tabs.get_tab_control(index) as JT_InspectorTab);
	return result;

func _get_active_tab() -> JT_InspectorTab:
	if _tabs.current_tab < 0 or _tabs.current_tab >= _tabs.get_tab_count(): return null;
	return _tabs.get_current_tab_control() as JT_InspectorTab;

func _select_tab(itab: JT_InspectorTab) -> void:
	if not _closing and is_instance_valid(itab) and itab.get_parent() == _tabs:
		_tabs.current_tab = _tabs.get_tab_idx_from_control(itab);

func _on_merge_handle_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton;
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return;
	if mouse_event.pressed and is_merge_ready() and mode == Window.MODE_WINDOWED:
		_merge_handle.accept_event();
		merge_drag_started.emit();

func _sync_window_state() -> void:
	if _closing or _tab_change_depth > 0: return;
	if _views.is_empty():
		close_inspector();
		return;
	_update_window_title();
	_update_detach_availability();
	_queue_history_refresh();

func _update_tab_title(itab: JT_InspectorTab) -> void:
	if _closing or not is_instance_valid(itab) or itab.get_parent() != _tabs: return;
	var tab_index: int = _tabs.get_tab_idx_from_control(itab);
	if tab_index < 0: return;
	_tabs.set_tab_title(tab_index, itab.get_target_title());
	_tabs.set_tab_tooltip(tab_index, " ");
	_tabs.set_tab_button_icon(tab_index, _tabs.get_theme_icon("Close", "EditorIcons"));
	_update_window_title();

func _update_window_title() -> void:
	if _tabs.current_tab < 0 or _tabs.current_tab >= _tabs.get_tab_count(): return;
	var active_tab: JT_InspectorTab = _tabs.get_current_tab_control() as JT_InspectorTab;
	if is_instance_valid(active_tab):
		title = "%s — Detached Inspectors (%d)" % [
			active_tab.get_target_title(), _views.size()];

func _build_toolbar(layout: VBoxContainer) -> void:
	var toolbar: HBoxContainer = HBoxContainer.new();
	toolbar.name = "InspectorToolbar";
	layout.add_child(toolbar);
	_detach_button = Button.new();
	_detach_button.name = "DetachTabButton";
	_detach_button.text = "Detach";
	_detach_button.icon = _toolbar_icon(&"ExternalLink", &"Node");
	_detach_button.tooltip_text = "Detach the active tab into a new window";
	_detach_button.disabled = true;
	_detach_button.pressed.connect(_on_detach_pressed);
	toolbar.add_child(_detach_button);
	_merge_handle = Button.new();
	_merge_handle.name = "MergeDragHandle";
	_merge_handle.text = "Drag to merge";
	_merge_handle.icon = _toolbar_icon(&"TabContainer", &"TabBar");
	_merge_handle.clip_text = true;
	_merge_handle.custom_minimum_size.x = 96.0 * EditorInterface.get_editor_scale();
	_merge_handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	_merge_handle.tooltip_text = "Drag onto another inspector's merge button; Esc cancels";
	_merge_handle.mouse_default_cursor_shape = Control.CURSOR_MOVE;
	_merge_handle.focus_mode = Control.FOCUS_NONE;
	_merge_handle.gui_input.connect(_on_merge_handle_input);
	toolbar.add_child(_merge_handle);
	_pin_button = CheckButton.new();
	_pin_button.name = "PinOnTopButton";
	_pin_button.text = "Pin on top";
	_pin_button.tooltip_text = "Keep this window above other windows";
	_pin_button.set_pressed_no_signal(true);
	_pin_button.toggled.connect(_on_pin_toggled);
	toolbar.add_child(_pin_button);
	toolbar.minimum_size_changed.connect(_update_toolbar_minimum.bind(toolbar));
	_update_toolbar_minimum(toolbar);

func _toolbar_icon(preferred: StringName, fallback: StringName) -> Texture2D:
	for icon_name: StringName in [preferred, fallback]:
		if has_theme_icon(icon_name, &"EditorIcons"):
			return get_theme_icon(icon_name, &"EditorIcons");
	return null;

func _update_toolbar_minimum(toolbar: HBoxContainer) -> void:
	if _closing: return;
	var editor_scale: float = EditorInterface.get_editor_scale();
	min_size.x = maxi(roundi(320.0 * editor_scale),
		ceili(toolbar.get_combined_minimum_size().x + 16.0 * editor_scale));

func _update_detach_availability() -> void:
	if not is_instance_valid(_detach_button): return;
	_detach_button.disabled = not can_detach_active_tab();
	_detach_button.tooltip_text = (
		"This tab already has its own window" if _views.size() == 1
		else "Detach the active tab into a new window");

func _on_detach_pressed() -> void:
	if validate_context() and can_detach_active_tab():
		detach_tab_requested.emit();

func _on_pin_toggled(pinned: bool) -> void:
	if not _closing: always_on_top = pinned;

func _shortcut_input(event: InputEvent) -> void:
	if _closing or not visible or not has_focus(): return;
	var key_event: InputEventKey = event as InputEventKey;
	if key_event == null or not key_event.pressed or key_event.echo: return;
	if not key_event.is_command_or_control_pressed() or key_event.alt_pressed: return;
	var focused_control: Control = gui_get_focus_owner();
	if focused_control is LineEdit or focused_control is TextEdit: return;
	if key_event.keycode == KEY_Z:
		set_input_as_handled();
		_perform_history_action(key_event.shift_pressed);
	elif key_event.keycode == KEY_Y and not key_event.shift_pressed:
		set_input_as_handled();
		_perform_history_action(true);

func _get_scene_history() -> UndoRedo:
	if not validate_context() or not is_instance_valid(_history_manager): return null;
	if _history_manager.is_committing_action(): return null;
	if _tabs.current_tab < 0 or _tabs.current_tab >= _tabs.get_tab_count(): return null;
	
	var active_tab: JT_InspectorTab = _tabs.get_current_tab_control() as JT_InspectorTab;
	if not is_instance_valid(active_tab) or not active_tab.validate_context():
		return null;
	
	if _history_manager.get_object_history_id(_get_scene_root()) != _history_id:
		close_inspector();
		return null;
	
	return _history_manager.get_history_undo_redo(_history_id);

func _perform_history_action(redo_action: bool) -> void:
	var history: UndoRedo = _get_scene_history()
	if not is_instance_valid(history) or history.is_committing_action(): return;
	if redo_action and history.has_redo(): history.redo();
	elif not redo_action and history.has_undo(): history.undo();
	if not _closing: _queue_history_refresh();

func _queue_history_refresh() -> void:
	if _closing or _history_refresh_queued: return;
	_history_refresh_queued = true;
	_refresh_history_controls.call_deferred();

func _refresh_history_controls() -> void:
	_history_refresh_queued = false;
	if _closing: return;
	_get_scene_history();
	if _closing: return;
	_update_detach_availability();

func _detach_scene() -> void:
	var scroot: Node = _get_scene_root();
	if is_instance_valid(scroot) and scroot.tree_exiting.is_connected(close_inspector):
		scroot.tree_exiting.disconnect(close_inspector);
	if is_instance_valid(_history_manager):
		if _history_manager.history_changed.is_connected(_queue_history_refresh):
			_history_manager.history_changed.disconnect(_queue_history_refresh);
		if _history_manager.version_changed.is_connected(_queue_history_refresh):
			_history_manager.version_changed.disconnect(_queue_history_refresh);
	_history_manager = null;
	_history_id = EditorUndoRedoManager.INVALID_HISTORY;
	_scene_ref = null;

func _get_scene_root() -> Node:
	return _scene_ref.get_ref() as Node if _scene_ref != null else null;

#endregion

#region Public Methods

func inspect_node(target: Node, scroot: Node, history: EditorUndoRedoManager) -> bool:
	if _closing or not is_instance_valid(_tabs) or not is_instance_valid(target):
		return false;
	if not is_instance_valid(scroot) or not is_instance_valid(history):
		return false;
	if _scene_ref == null and not _bind_scene(scroot, history):
		close_inspector();
		return false;
	elif scroot != _get_scene_root() or history != _history_manager:
		close_inspector();
		return false;
	
	var itab: JT_InspectorTab = JT_InspectorTab.new();
	itab.name = "InspectorTab";
	_tab_change_depth += 1;
	_tabs.add_child(itab);
	_register_tab(itab);
	var bound: bool = itab.inspect_node(target, scroot)
	if not bound: itab.close_inspector();
	_tab_change_depth -= 1;
	if not bound or _closing:
		if not _closing and _views.is_empty(): close_inspector();
		return false;
	
	_update_tab_title(itab);
	_tabs.current_tab = _tabs.get_tab_idx_from_control(itab);
	_sync_window_state();
	focus_inspector();
	return not _closing;

func set_placement_index(index: int) -> void:
	_placement_index = index;

func get_view_revision() -> int:
	return _view_revision;

func is_merge_ready() -> bool:
	return (not _closing and not is_queued_for_deletion() and is_inside_tree()
		and visible and mode != Window.MODE_MINIMIZED and _tab_change_depth == 0
		and not _views.is_empty() and _scene_is_valid()
		and is_instance_valid(_history_manager) and not _history_manager.is_committing_action());

func can_merge_with(other: Variant) -> bool:
	if not is_instance_valid(other) or other == self or other.get_script() != get_script():
		return false;
	return (is_merge_ready() and other.is_merge_ready()
		and _get_scene_root() == other._get_scene_root()
		and _history_manager == other._history_manager and _history_id == other._history_id);

func get_merge_drop_rect() -> Rect2:
	if not is_merge_ready(): return Rect2()
	return _merge_handle.get_screen_transform() * Rect2(Vector2.ZERO, _merge_handle.size)

func set_merge_highlight(highlighted: bool) -> void:
	if _closing or not is_instance_valid(_merge_handle): return;
	_merge_handle.text = "Release to merge here" if highlighted else "Drag to merge";
	for color_name: StringName in [&"font_color", &"font_hover_color"]:
		if highlighted:
			_merge_handle.add_theme_color_override(
				color_name, get_theme_color(&"accent_color", &"Editor"));
		else:
			_merge_handle.remove_theme_color_override(color_name);

func merge_from(source: Variant) -> bool:
	if not can_merge_with(source): return false;
	return _transfer_from(source, source._ordered_tabs());

func can_detach_active_tab() -> bool:
	if not is_merge_ready() or _views.size() <= 1: return false;
	var active_tab: JT_InspectorTab = _get_active_tab();
	return (is_instance_valid(active_tab) 
		and not active_tab.is_queued_for_deletion()
		and _views.has(active_tab.get_instance_id()));

func receive_detached_tab(source: Variant) -> bool:
	if _closing or not _views.is_empty() or _scene_ref != null: return false;
	if not is_instance_valid(source) or source.get_script() != get_script(): return false;
	if not source.validate_context() or not source.can_detach_active_tab(): return false;
	
	var active_tab: JT_InspectorTab = source._get_active_tab();
	if not _bind_scene(source._get_scene_root(), source._history_manager):
		return false;
	
	current_screen = source.current_screen;
	var screen_rect: Rect2i = DisplayServer.screen_get_usable_rect(current_screen);
	size = source.size.min(screen_rect.size);
	always_on_top = source.always_on_top;
	_pin_button.set_pressed_no_signal(always_on_top);
	var offset: int = roundi(32.0 * EditorInterface.get_editor_scale());
	position = (source.position + Vector2i.ONE * offset).clamp(
		screen_rect.position, screen_rect.position 
		+ (screen_rect.size - size).max(Vector2i.ZERO));
	_positioned = true;
	var moving_tabs: Array[JT_InspectorTab] = [active_tab];
	return _transfer_from(source, moving_tabs, true);

func focus_inspector() -> void:
	if not validate_context(): return;
	if not _positioned:
		var editor_window: Window = EditorInterface.get_base_control().get_window();
		current_screen = editor_window.current_screen;
		var screen_rect: Rect2i = DisplayServer.screen_get_usable_rect(current_screen);
		size = size.min(Vector2i(Vector2(screen_rect.size) * 0.85));
		position = screen_rect.position + Vector2i(Vector2(screen_rect.size - size) * 0.5);
		var stagger: int = roundi(28.0 * EditorInterface.get_editor_scale());
		position += Vector2i.ONE * stagger * (_placement_index % 8);
		position = position.clamp(screen_rect.position, screen_rect.end - size);
		_positioned = true;
	if mode == Window.MODE_MINIMIZED: mode = Window.MODE_WINDOWED
	show(); grab_focus();

func close_inspector() -> void:
	if _closing: return;
	_closing = true;
	_tab_change_depth += 1;
	for itab: JT_InspectorTab in _views.values():
		if is_instance_valid(itab): itab.close_inspector()
	_views.clear();
	_tab_change_depth -= 1;
	_detach_scene();
	set_process_shortcut_input(false);
	always_on_top = false;
	hide();
	inspector_closed.emit();
	queue_free();

func validate_context() -> bool:
	if _closing: return false;
	if not _scene_is_valid():
		close_inspector();
		return false;
	if _tab_change_depth > 0 or _validating_tabs: return true;
	_validating_tabs = true;
	_tab_change_depth += 1;
	for itab: JT_InspectorTab in _views.values():
		if is_instance_valid(itab) and itab.validate_context():
			itab.refresh_title();
	_tab_change_depth -= 1;
	_validating_tabs = false;
	if _views.is_empty():
		close_inspector();
		return false;
	_update_window_title();
	_update_detach_availability();
	return not _closing;

#endregion
