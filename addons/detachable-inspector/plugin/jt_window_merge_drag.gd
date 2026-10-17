@tool
extends RefCounted

const InspectorWindow = preload("res://addons/detachable-inspector/plugin/jt_inspector_window.gd")

var _source_ref: WeakRef
var _hover_ref: WeakRef
var _source_revision: int = 0
var _hover_revision: int = 0
var _original_position: Vector2i
var _start_pointer: Vector2i
var _moving: bool = false


func begin(source: InspectorWindow) -> bool:
	cancel()
	if not source.is_merge_ready() or source.mode != Window.MODE_WINDOWED:
		return false
	_source_ref = weakref(source)
	_source_revision = source.get_view_revision()
	_original_position = source.position
	_start_pointer = DisplayServer.mouse_get_position()
	return true


func involves(inspector_window: InspectorWindow) -> bool:
	return inspector_window == _get_source() or inspector_window == _get_hover()


func update(windows: Array) -> bool:
	var source: InspectorWindow = _get_source()
	if not is_instance_valid(source):
		cancel()
		return false
	if (
		not source.is_merge_ready() or source.get_view_revision() != _source_revision
		or Input.is_key_pressed(KEY_ESCAPE) or Window.get_focused_window() == null
	):
		cancel()
		return false
	var hovered: InspectorWindow = _get_hover()
	if _hover_ref != null and (
		not is_instance_valid(hovered) or not hovered.can_merge_with(source)
		or hovered.get_view_revision() != _hover_revision
	):
		cancel()
		return false
	var pointer: Vector2i = DisplayServer.mouse_get_position()
	var editor_scale: float = EditorInterface.get_editor_scale()
	if Vector2(pointer - _start_pointer).length() >= 8.0 * editor_scale:
		_moving = true
	if _moving:
		# Keep the real source window clear of the cursor and destination strip.
		var decoration_inset: Vector2i = source.position - source.get_position_with_decorations()
		source.position = (
			pointer + decoration_inset.max(Vector2i.ZERO)
			+ Vector2i.ONE * roundi(16.0 * editor_scale)
		)
		_set_hover(_find_destination(source, pointer, windows))
	if (DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT) != 0:
		return true
	var destination: InspectorWindow = _get_hover()
	var original_position: Vector2i = _original_position
	var should_merge: bool = _moving and is_instance_valid(destination)
	_clear_state()
	# Clear drag ownership before a successful merge closes/emits from its source.
	if should_merge and destination.merge_from(source):
		return false
	if is_instance_valid(source) and not source.is_queued_for_deletion():
		source.position = original_position
	return false


func cancel() -> void:
	var source: InspectorWindow = _get_source()
	var original_position: Vector2i = _original_position
	_clear_state()
	if is_instance_valid(source) and not source.is_queued_for_deletion():
		source.position = original_position


func _find_destination(
	source: InspectorWindow, pointer: Vector2i, windows: Array
) -> InspectorWindow:
	var destination: InspectorWindow
	for candidate: InspectorWindow in windows:
		if not is_instance_valid(candidate) or not candidate.can_merge_with(source):
			continue
		if not candidate.get_merge_drop_rect().has_point(Vector2(pointer)):
			continue
		if destination != null:
			return null # Overlapping drop strips are ambiguous; never guess.
		destination = candidate
	if destination == null:
		return null
	# Do not drop through another application, editor window or native popup.
	if DisplayServer.get_window_at_screen_position(pointer) != destination.get_window_id():
		return null
	return destination


func _set_hover(destination: InspectorWindow) -> void:
	var previous: InspectorWindow = _get_hover()
	if previous == destination:
		return
	if is_instance_valid(previous):
		previous.set_merge_highlight(false)
	_hover_ref = weakref(destination) if destination != null else null
	if destination != null:
		_hover_revision = destination.get_view_revision()
		destination.set_merge_highlight(true)


func _clear_state() -> void:
	_set_hover(null)
	_hover_ref = null
	_hover_revision = 0
	_source_ref = null
	_source_revision = 0
	_moving = false


func _get_source() -> InspectorWindow:
	return _source_ref.get_ref() as InspectorWindow if _source_ref != null else null


func _get_hover() -> InspectorWindow:
	return _hover_ref.get_ref() as InspectorWindow if _hover_ref != null else null
