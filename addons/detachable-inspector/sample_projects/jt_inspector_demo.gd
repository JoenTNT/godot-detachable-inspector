# Detachable Inspector - Copyright (C) 2026 | JoenTNT
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See <https://www.gnu.org/licenses/gpl-3.0.html> for the full license.

@tool
class_name JT_InspectorDemo
extends Node2D

# Local Enums.
enum PreviewShape { RECTANGLE, CIRCLE }

# Properties.
@export var preview_enabled: bool = true:
	set(value):
		preview_enabled = value;
		_queue_preview_redraw();

@export var preview_shape: PreviewShape = PreviewShape.RECTANGLE:
	set(value):
		preview_shape = value;
		_queue_preview_redraw();

@export var preview_size: Vector2 = Vector2(144.0, 96.0):
	set(value):
		preview_size = value;
		_queue_preview_redraw();

@export var preview_offset: Vector2 = Vector2.ZERO:
	set(value):
		preview_offset = value;
		_queue_preview_redraw();

@export var preview_color: Color = Color(0.3, 0.75, 1.0):
	set(value):
		preview_color = value;
		_queue_preview_redraw();

@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0:
	set(value):
		opacity = value;
		_queue_preview_redraw();

@export_range(0, 32, 1) 
var count: int = 4;

@export 
var display_name: String = "Inspector Demo";

@export_multiline 
var notes: String = """Edit Preview values to change the shape.
Other values demonstrate Inspector controls.""";

@export_flags("Movement", "Interaction", "Effects") 
var features: int = 3;

@export 
var direction_3d: Vector3 = Vector3.UP;

@export 
var labels: Array[String] = ["First", "Second", "Third"];

@export_node_path("Marker2D") 
var target_path: NodePath = ^"ReferenceTarget";

@export 
var example_curve: Curve;

@export_tool_button("Print Values")
var print_values: Callable = _print_values;

@export_tool_button("Refresh Preview", "Node2D")
var refresh_preview: Callable = _refresh_preview;

func _enter_tree() -> void:
	queue_redraw();

func _draw() -> void:
	if not preview_enabled: return;
	var size = preview_size.abs().max(Vector2.ONE);
	var color = preview_color;
	color.a *= clampf(opacity, 0.0, 1.0);
	
	match preview_shape:
		PreviewShape.RECTANGLE:
			draw_rect(Rect2(preview_offset - size * 0.5, size), color);
		PreviewShape.CIRCLE:
			draw_circle(preview_offset, minf(size.x, size.y) * 0.5, color);

func _queue_preview_redraw() -> void:
	if is_inside_tree(): queue_redraw();

func _print_values() -> void:
	if not Engine.is_editor_hint(): return;
	
	var values: Dictionary = {
		"preview_enabled": preview_enabled, "preview_shape": preview_shape,
		"preview_size": preview_size, "preview_offset": preview_offset,
		"preview_color": preview_color, "opacity": opacity, "count": count,
		"display_name": display_name, "notes": notes, "features": features,
		"direction_3d": direction_3d, "labels": labels,
		"target_path": target_path, "example_curve": example_curve,
	};
	
	print("Detached Inspector demo values:")
	for property_name: String in values:
		print("  ", property_name, ": ", values[property_name]);

func _refresh_preview() -> void:
	if Engine.is_editor_hint(): _queue_preview_redraw();
