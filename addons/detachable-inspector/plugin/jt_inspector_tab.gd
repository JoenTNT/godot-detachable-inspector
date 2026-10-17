# Detachable Inspector - Copyright (C) 2026 | JoenTNT
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See <https://www.gnu.org/licenses/gpl-3.0.html> for the full license.

@tool
class_name JT_InspectorTab
extends VBoxContainer

# Events.
signal inspector_closed();
signal target_title_changed();

# Runtime variable data.
var _inspector: EditorInspector;
var _filter: LineEdit;
var _target_ref: WeakRef;
var _scene_ref: WeakRef;
var _closing: bool = false;
var _transferring: bool = false;
var _title: String = "Inspector";
var _target_path: String = "";

func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free();
		return;
		
	if not ClassDB.class_has_method(&"EditorInspector", &"create_default_inspector"):
		push_error("Detached Inspector: the default inspector factory is unavailable.");
		return;

	_filter = LineEdit.new();
	_filter.name = "PropertyFilter";
	_filter.placeholder_text = "Filter properties";
	_filter.clear_button_enabled = true;
	add_child(_filter);
	_inspector = ClassDB.class_call_static(&"EditorInspector", &"create_default_inspector", 
		_filter) as EditorInspector
	
	if not is_instance_valid(_inspector):
		push_error("Detached Inspector: could not create the editor inspector.");
		return;
	
	_inspector.name = "PinnedInspector";
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL;
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL;
	add_child(_inspector);
	visibility_changed.connect(_on_visibility_changed);
	_on_visibility_changed();

func inspect_node(target: Node, scene_root: Node) -> bool:
	if _closing or not is_instance_valid(_inspector) or _target_ref != null:
		return false;
	
	_target_ref = weakref(target);
	_scene_ref = weakref(scene_root);
	if not validate_context():
		return false;
	
	target.tree_exiting.connect(close_inspector);
	target.renamed.connect(refresh_title);
	target.script_changed.connect(close_inspector);
	target.property_list_changed.connect(close_inspector);
	refresh_title();
	_inspector.edit(target);
	return validate_context();

func validate_context() -> bool:
	if _closing: return false;
	
	var target: Node = _get_target();
	var scene_root: Node = _scene_ref.get_ref() as Node if _scene_ref != null else null;
	
	if not is_instance_valid(target) or not is_instance_valid(scene_root):
		close_inspector();
		return false;
	
	if not target.is_inside_tree() or not scene_root.is_inside_tree():
		close_inspector();
		return false;
	
	if target.is_queued_for_deletion() or scene_root.is_queued_for_deletion():
		close_inspector();
		return false;
	
	if EditorInterface.get_edited_scene_root() != scene_root:
		close_inspector();
		return false;
	
	if target != scene_root and not scene_root.is_ancestor_of(target):
		close_inspector();
		return false;
	
	return true;


func refresh_title() -> void:
	if not validate_context(): return;
	
	var target: Node = _get_target();
	var node_title: String = str(target.name);
	var node_path: String = "%s (%s)" % [target.get_path(), target.get_class()];
	
	if _title == node_title and _target_path == node_path: return;
	
	_title = node_title;
	_target_path = node_path;
	_filter.tooltip_text = node_path;
	target_title_changed.emit();

func get_target_title() -> String:
	return _title;

func get_target_path() -> String:
	return _target_path;

func close_inspector() -> void:
	if _closing: return;
	_closing = true;
	_stop_inspector();
	_detach_target();
	hide();
	inspector_closed.emit();
	queue_free();

func _exit_tree() -> void:
	if _transferring: return;
	_closing = true;
	_stop_inspector();
	_detach_target();

func _on_visibility_changed() -> void:
	if not _closing and not _transferring:
		process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() else Node.PROCESS_MODE_DISABLED;

func begin_transfer() -> bool:
	if _transferring or not validate_context() or is_queued_for_deletion():
		return false;
	
	_transferring = true;
	return true;

func end_transfer() -> void:
	_transferring = false;
	if validate_context():
		_on_visibility_changed();

func _stop_inspector() -> void:
	if not is_instance_valid(_inspector): return;
	_disable_ui_processing(_inspector);
	_inspector.hide();
	_inspector.edit(null);

func _disable_ui_processing(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED;
	node.set_process_internal(false);
	for child: Node in node.get_children(true):
		_disable_ui_processing(child);

func _detach_target() -> void:
	var target: Node = _get_target();
	if is_instance_valid(target):
		if target.tree_exiting.is_connected(close_inspector):
			target.tree_exiting.disconnect(close_inspector);
		if target.renamed.is_connected(refresh_title):
			target.renamed.disconnect(refresh_title);
		if target.script_changed.is_connected(close_inspector):
			target.script_changed.disconnect(close_inspector);
		if target.property_list_changed.is_connected(close_inspector):
			target.property_list_changed.disconnect(close_inspector);
	_target_ref = null;
	_scene_ref = null;

func _get_target() -> Node:
	return _target_ref.get_ref() as Node if _target_ref != null else null;
