# Detachable Inspector - Copyright (C) 2026 | JoenTNT
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See <https://www.gnu.org/licenses/gpl-3.0.html> for the full license.

@tool
class_name JT_SceneTreeContextMenu
extends EditorContextMenuPlugin

# Events.
signal open_requested(target: Node);

# Constants.
const ACTION_NAME: String = "Open in Detached Inspector";
const ICON_NAME: StringName = &"ExternalLink";

# Runtime variable data.
var _active: bool = true;

#region Private Methods

func _popup_menu(paths: PackedStringArray) -> void:
	if not _active or not Engine.is_editor_hint() or paths.size() != 1: return;
	var scene_root: Node = EditorInterface.get_edited_scene_root();
	if not is_instance_valid(scene_root) or paths[0].is_empty(): return;
	var target: Node = scene_root.get_node_or_null(NodePath(paths[0]));
	if not _is_local_target(target, scene_root): return;
	add_context_menu_item(ACTION_NAME, _open_context_node.bind(weakref(target), 
		weakref(scene_root)), _get_menu_icon());

func _open_context_node(nodes: Array, target_ref: WeakRef, scene_ref: WeakRef) -> void:
	if not _active or nodes.size() != 1: return;
	var target: Node = target_ref.get_ref() as Node;
	var scene_root: Node = scene_ref.get_ref() as Node;
	if not _is_local_target(target, scene_root): return;
	if not is_instance_valid(nodes[0]) or nodes[0] != target: return;
	open_requested.emit(target);

func _is_local_target(target: Node, scene_root: Node) -> bool:
	if not is_instance_valid(target) or not is_instance_valid(scene_root): return false;
	if not target.is_inside_tree() or not scene_root.is_inside_tree(): return false;
	if target.is_queued_for_deletion() or scene_root.is_queued_for_deletion(): return false;
	return (EditorInterface.get_edited_scene_root() == scene_root
		and (target == scene_root or scene_root.is_ancestor_of(target)));

func _get_menu_icon() -> Texture2D:
	var editor_theme: Theme = EditorInterface.get_editor_theme();
	if editor_theme.has_icon(ICON_NAME, &"EditorIcons"):
		return editor_theme.get_icon(ICON_NAME, &"EditorIcons");
	if editor_theme.has_icon(&"Node", &"EditorIcons"):
		return editor_theme.get_icon(&"Node", &"EditorIcons");
	return null;

#endregion

#region Public Methods

func deactivate() -> void: _active = false;

#endregion
