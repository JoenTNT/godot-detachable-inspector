# Detachable Inspector - Copyright (C) 2026 | JoenTNT
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See <https://www.gnu.org/licenses/gpl-3.0.html> for the full license.

@tool
class_name JT_WindowMergeDrag
extends RefCounted

# Runtime variable data.
var _source_ref: WeakRef;
var _hover_ref: WeakRef;
var _source_revision: int = 0;
var _hover_revision: int = 0;
var _original_position: Vector2i;
var _start_pointer: Vector2i;
var _moving: bool = false;

func begin(source: JT_InspectorWindow) -> bool:
	cancel();
	if not source.is_merge_ready() or source.mode != Window.MODE_WINDOWED:
		return false;
	_source_ref = weakref(source);
	_source_revision = source.get_view_revision();
	_original_position = source.position;
	_start_pointer = DisplayServer.mouse_get_position();
	return true;

func involves(inspector_window: JT_InspectorWindow) -> bool:
	return inspector_window == _get_source() or inspector_window == _get_hover()

func update(windows: Array) -> bool:
	var source: JT_InspectorWindow = _get_source();
	if not is_instance_valid(source):
		cancel();
		return false;
	
	if (not source.is_merge_ready() or source.get_view_revision() != _source_revision
		or Input.is_key_pressed(KEY_ESCAPE) or Window.get_focused_window() == null):
		cancel();
		return false;
	
	var hovered: JT_InspectorWindow = _get_hover();
	if _hover_ref != null and (
		not is_instance_valid(hovered) or not hovered.can_merge_with(source)
		or hovered.get_view_revision() != _hover_revision):
		cancel();
		return false;
	
	var pointer: Vector2i = DisplayServer.mouse_get_position();
	var editor_scale: float = EditorInterface.get_editor_scale();
	if Vector2(pointer - _start_pointer).length() >= 8.0 * editor_scale:
		_moving = true;
	
	if _moving:
		var decoration_inset: Vector2i = source.position - source.get_position_with_decorations()
		source.position = (pointer + decoration_inset.max(Vector2i.ZERO)
			+ Vector2i.ONE * roundi(16.0 * editor_scale));
		_set_hover(_find_destination(source, pointer, windows));
	
	if (DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT) != 0:
		return true;
	
	var destination: JT_InspectorWindow = _get_hover();
	var original_position: Vector2i = _original_position;
	var should_merge: bool = _moving and is_instance_valid(destination);
	_clear_state();
	
	if should_merge and destination.merge_from(source): return false;
	if is_instance_valid(source) and not source.is_queued_for_deletion():
		source.position = original_position;
	
	return false;

func cancel() -> void:
	var source: JT_InspectorWindow = _get_source();
	var original_position: Vector2i = _original_position;
	_clear_state();
	if is_instance_valid(source) and not source.is_queued_for_deletion():
		source.position = original_position;

func _find_destination(source: JT_InspectorWindow, pointer: Vector2i, windows: Array) -> JT_InspectorWindow:
	var destination: JT_InspectorWindow;
	for candidate: JT_InspectorWindow in windows:
		if not is_instance_valid(candidate) or not candidate.can_merge_with(source): continue;
		if not candidate.get_merge_drop_rect().has_point(Vector2(pointer)): continue;
		if destination != null: return null;
		destination = candidate;
	
	if destination == null: return null;
	if DisplayServer.get_window_at_screen_position(pointer) != destination.get_window_id():
		return null;
	
	return destination;

func _set_hover(destination: JT_InspectorWindow) -> void:
	var previous: JT_InspectorWindow = _get_hover();
	if previous == destination: return;
	if is_instance_valid(previous): previous.set_merge_highlight(false);
	_hover_ref = weakref(destination) if destination != null else null;
	if destination != null:
		_hover_revision = destination.get_view_revision();
		destination.set_merge_highlight(true);

func _clear_state() -> void:
	_set_hover(null);
	_hover_ref = null;
	_hover_revision = 0;
	_source_ref = null;
	_source_revision = 0;
	_moving = false;

func _get_source() -> JT_InspectorWindow:
	return _source_ref.get_ref() as JT_InspectorWindow if _source_ref != null else null;

func _get_hover() -> JT_InspectorWindow:
	return _hover_ref.get_ref() as JT_InspectorWindow if _hover_ref != null else null;
