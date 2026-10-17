# Detachable Inspector - Copyright (C) 2026 | JoenTNT
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See <https://www.gnu.org/licenses/gpl-3.0.html> for the full license.

@tool
extends EditorPlugin

# Constants.
const MENU_NAME: String = "Open Detached Inspector"

# Runtime variable data.
var _inspector_windows: Dictionary[int, JT_InspectorWindow] = {};
var _merge_drag: JT_WindowMergeDrag;
var _window_creation_index: int = 0;
var _scene_tree_context_menu: JT_SceneTreeContextMenu;
var _message_dialog: AcceptDialog;
var _menu_registered: bool = false;
var _validating_windows: bool = false;

func _enter_tree() -> void:
	set_process(false);
	if not Engine.is_editor_hint(): return;
	if not ClassDB.class_has_method(&"EditorInspector", &"create_default_inspector"):
		push_error("Detached Inspector requires Godot 4.7+ with the default inspector factory.");
		return;
	_merge_drag = JT_WindowMergeDrag.new();
	_message_dialog = AcceptDialog.new();
	_message_dialog.name = "DetachedInspectorMessage";
	_message_dialog.title = "Detached Inspector";
	EditorInterface.get_base_control().add_child(_message_dialog);
	add_tool_menu_item(MENU_NAME, _open_selected_inspector);
	_menu_registered = true;
	_scene_tree_context_menu = JT_SceneTreeContextMenu.new();
	_scene_tree_context_menu.open_requested.connect(_open_inspector_for_node)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCENE_TREE,
		_scene_tree_context_menu);
	scene_changed.connect(_on_scene_changed);
	scene_closed.connect(_on_scene_closed);
	get_tree().tree_changed.connect(_validate_windows);

func _exit_tree() -> void:
	if is_instance_valid(_scene_tree_context_menu):
		_scene_tree_context_menu.deactivate();
		_scene_tree_context_menu.open_requested.disconnect(_open_inspector_for_node);
		remove_context_menu_plugin(_scene_tree_context_menu);
		_scene_tree_context_menu = null;
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed);
	if scene_closed.is_connected(_on_scene_closed):
		scene_closed.disconnect(_on_scene_closed);
	if get_tree().tree_changed.is_connected(_validate_windows):
		get_tree().tree_changed.disconnect(_validate_windows);
	if _menu_registered:
		remove_tool_menu_item(MENU_NAME);
		_menu_registered = false;
	_close_windows();
	_merge_drag = null;
	if is_instance_valid(_message_dialog):
		_message_dialog.hide();
		_message_dialog.queue_free();
	_message_dialog = null;

func _open_selected_inspector() -> void:
	var selected_nodes: Array[Node] = EditorInterface.get_selection().get_selected_nodes();
	if selected_nodes.size() != 1:
		_show_message("Select exactly one node in the local Scene tree, then run this command.");
		return;
	_open_inspector_for_node(selected_nodes[0]);

func _open_inspector_for_node(target: Node) -> void:
	if not is_inside_tree() or not Engine.is_editor_hint(): return;
	var scene_root: Node = EditorInterface.get_edited_scene_root();
	if not is_instance_valid(target) or not is_instance_valid(scene_root):
		_show_message("Open a scene and select one of its nodes first.");
		return;
	var is_local_target: bool = target == scene_root or scene_root.is_ancestor_of(target);
	if (not target.is_inside_tree() or not scene_root.is_inside_tree()
		or target.is_queued_for_deletion() or scene_root.is_queued_for_deletion()
		or not is_local_target):
		_show_message("The selected node must belong to the active local scene.");
		return;
	if not DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		_show_message("This display driver does not support separate inspector windows.");
		return;
	var iwin: JT_InspectorWindow = _create_inspector_window();
	if not iwin.inspect_node(target, scene_root, get_undo_redo()):
		iwin.close_inspector();
		return;
	_inspector_windows[iwin.get_instance_id()] = iwin;
	_window_creation_index += 1;

func _create_inspector_window() -> JT_InspectorWindow:
	var iwin: JT_InspectorWindow = JT_InspectorWindow.new();
	iwin.name = "DetachedInspectorWindow";
	iwin.set_placement_index(_window_creation_index);
	iwin.inspector_closed.connect(_on_inspector_closed.bind(iwin));
	iwin.merge_drag_started.connect(_on_merge_drag_started.bind(iwin));
	iwin.detach_tab_requested.connect(_on_detach_tab_requested.bind(iwin));
	EditorInterface.get_base_control().add_child(iwin);
	return iwin;

func _on_detach_tab_requested(source_window: JT_InspectorWindow) -> void:
	_cancel_merge_drag();
	if not _inspector_windows.has(source_window.get_instance_id()): return;
	if not source_window.can_detach_active_tab(): return;
	var iwin: JT_InspectorWindow = _create_inspector_window();
	if not iwin.receive_detached_tab(source_window):
		iwin.close_inspector();
		return;
	_inspector_windows[iwin.get_instance_id()] = iwin;
	_window_creation_index += 1;

func _show_message(message: String) -> void:
	if not is_instance_valid(_message_dialog):
		push_warning(message);
		return;
	_message_dialog.dialog_text = message;
	_message_dialog.popup_centered();

func _on_inspector_closed(iwin: JT_InspectorWindow) -> void:
	if is_instance_valid(_merge_drag) and _merge_drag.involves(iwin):
		_cancel_merge_drag();
	_inspector_windows.erase(iwin.get_instance_id());

func _on_scene_changed(_scene_root: Node) -> void:
	_close_windows();

func _on_scene_closed(_scene_path: String) -> void:
	_validate_windows();

func _validate_windows() -> void:
	if _validating_windows: return;
	_validating_windows = true;
	for iwin: JT_InspectorWindow in _inspector_windows.values():
		if is_instance_valid(iwin):
			iwin.validate_context();
	_validating_windows = false;

func _close_windows() -> void:
	_cancel_merge_drag();
	var windows: Array = _inspector_windows.values();
	_inspector_windows.clear();
	for iwin: JT_InspectorWindow in windows:
		if is_instance_valid(iwin):
			iwin.close_inspector();

func _on_merge_drag_started(iwin: JT_InspectorWindow) -> void:
	_cancel_merge_drag();
	if not _inspector_windows.has(iwin.get_instance_id()): return;
	if is_instance_valid(_merge_drag):
		set_process(_merge_drag.begin(iwin))

func _process(_delta: float) -> void:
	if not is_instance_valid(_merge_drag) or not _merge_drag.update(
		_inspector_windows.values()):
		set_process(false);

func _cancel_merge_drag() -> void:
	set_process(false);
	if is_instance_valid(_merge_drag):
		_merge_drag.cancel();
