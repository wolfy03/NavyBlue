extends CanvasLayer
class_name PerformanceOverlay
## Development performance HUD, toggled with F3.
##
## The overlay samples frame times every frame (cheap: one ring-buffer write)
## but rebuilds its label text only on `display_refresh_interval_sec`, so the
## overlay itself never becomes the bottleneck it is meant to find.

const TOGGLE_ACTION := &"toggle_performance_overlay"

@export var display_refresh_interval_sec := 0.25
@export var sample_window_sec := 10.0
@export var start_visible := false

var counters: BattlePerformanceCounters
var _label: Label
var _panel: PanelContainer
var _refresh_elapsed_sec := 0.0
var _visible := false


func _ready() -> void:
	layer = 128
	_build_ui()
	set_overlay_visible(start_visible)
	# The overlay must keep sampling while the game is paused for a hitch.
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(
		next_counters: BattlePerformanceCounters,
		next_visible: bool = false
) -> void:
	counters = next_counters
	if counters != null:
		counters.set_sample_window_sec(sample_window_sec)
		counters.set_enabled(true)
	set_overlay_visible(next_visible)


func set_overlay_visible(value: bool) -> void:
	_visible = value
	if _panel != null:
		_panel.visible = value
	# Sampling continues while hidden so toggling on shows a populated window.
	set_process(true)


func is_overlay_visible() -> bool:
	return _visible


func toggle() -> void:
	set_overlay_visible(not _visible)


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action(TOGGLE_ACTION):
		return
	if event.is_action_pressed(TOGGLE_ACTION):
		toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if counters == null:
		return
	counters.record_frame_time(delta * 1000.0)
	if not _visible:
		return
	_refresh_elapsed_sec += delta
	if _refresh_elapsed_sec < maxf(display_refresh_interval_sec, 0.05):
		return
	_refresh_elapsed_sec = 0.0
	_label.text = build_display_text(counters.make_snapshot())


## Separated from _process so tests can assert the formatting without a frame.
static func build_display_text(
		snapshot: BattlePerformanceSnapshot
) -> String:
	var lines := PackedStringArray()
	lines.append("FPS: %d   avg %.0f   1%% low %.0f   min %.0f" % [
		snapshot.fps,
		snapshot.average_fps,
		snapshot.one_percent_low_fps,
		snapshot.minimum_fps,
	])
	lines.append("Frame max: %.1f ms" % snapshot.maximum_frame_time_ms)
	lines.append("Process: %.2f ms   Physics: %.2f ms" % [
		snapshot.process_time_ms,
		snapshot.physics_time_ms,
	])
	lines.append("")
	lines.append("Draw calls: %d   Rendered: %d" % [
		snapshot.draw_calls,
		snapshot.rendered_objects,
	])
	lines.append("Nodes: %d   Objects: %d" % [
		snapshot.node_count,
		snapshot.object_count,
	])
	lines.append("")
	lines.append("Projectiles: %d (secondary %d, peak %d)" % [
		snapshot.active_projectiles,
		snapshot.active_secondary_projectiles,
		snapshot.peak_active_projectiles,
	])
	lines.append("Trails: %d (peak %d)" % [
		snapshot.active_trails,
		snapshot.peak_active_trails,
	])
	lines.append("")
	lines.append("Secondary ships: %d   mounts: %d" % [
		snapshot.secondary_ships,
		snapshot.secondary_mounts_total,
	])
	lines.append("Evaluated/frame: %d   ready %d   fired %d" % [
		snapshot.secondary_mounts_evaluated,
		snapshot.secondary_mounts_ready,
		snapshot.secondary_mounts_fired,
	])
	lines.append("")
	lines.append("Group rebuild/frame: %d req, %d changed" % [
		snapshot.group_rebuilds_requested,
		snapshot.group_rebuilds_changed,
	])
	lines.append("Lead solve/frame: %d" % snapshot.lead_solves)
	lines.append("Accuracy solve/frame: %d" % snapshot.accuracy_solves)
	lines.append("LoF checks/frame: %d" % snapshot.line_of_fire_checks)
	lines.append(
		"Candidate-mount evals/scan: %d"
		% snapshot.candidate_mount_evaluations
	)
	return "\n".join(lines)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "PerformancePanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(12.0, 12.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	_panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.name = "PerformanceLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.86, 0.93, 1.0))
	_panel.add_child(_label)
	add_child(_panel)
