extends RefCounted
class_name BattlePerformanceCounters
## Shared per-frame counters for battle systems.
##
## Systems increment plain integers; nothing here walks the scene tree, emits
## signals, or allocates per call. Counters are handed out through
## BattleServices, never discovered from /root.
##
## When `enabled` is false the increment helpers return immediately, so leaving
## the instrumentation calls in release paths costs one boolean test.

const FRAME_SAMPLE_CAPACITY := 1024

var enabled := false

# Per-frame counters, cleared by begin_frame().
var secondary_mounts_evaluated := 0
var secondary_mounts_ready := 0
var secondary_mounts_fired := 0
var gunnery_group_rebuilds_requested := 0
var gunnery_group_rebuilds_changed := 0
var gunnery_lead_solves := 0
var gunnery_accuracy_solves := 0
var line_of_fire_checks := 0
var candidate_mount_evaluations := 0

# Live gauges, maintained by register/unregister pairs.
var active_projectiles := 0
var active_secondary_projectiles := 0
var active_trails := 0

# Structural gauges, refreshed by the owning systems.
var secondary_ships := 0
var secondary_mounts_total := 0

# Peaks, cleared only by reset_peaks().
var peak_active_projectiles := 0
var peak_active_trails := 0
var peak_secondary_mounts_evaluated := 0

var _frame_times_ms: PackedFloat32Array = PackedFloat32Array()
var _frame_sample_head := 0
var _frame_sample_count := 0
var _sample_window_sec := 10.0


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	if not enabled:
		_frame_sample_head = 0
		_frame_sample_count = 0


func set_sample_window_sec(value: float) -> void:
	_sample_window_sec = maxf(value, 0.5)


## Clears the per-frame counters. Live gauges and peaks survive.
func begin_frame() -> void:
	secondary_mounts_evaluated = 0
	secondary_mounts_ready = 0
	secondary_mounts_fired = 0
	gunnery_group_rebuilds_requested = 0
	gunnery_group_rebuilds_changed = 0
	gunnery_lead_solves = 0
	gunnery_accuracy_solves = 0
	line_of_fire_checks = 0
	candidate_mount_evaluations = 0
	secondary_ships = 0
	secondary_mounts_total = 0


## Records one frame duration into the ring buffer. Never sorts: the 1% low is
## computed only when a snapshot is requested.
func record_frame_time(frame_time_ms: float) -> void:
	if not enabled or not is_finite(frame_time_ms) or frame_time_ms <= 0.0:
		return
	var capacity := _get_sample_capacity()
	if _frame_times_ms.size() != capacity:
		_frame_times_ms.resize(capacity)
		_frame_sample_head = 0
		_frame_sample_count = 0
	_frame_times_ms[_frame_sample_head] = frame_time_ms
	_frame_sample_head = (_frame_sample_head + 1) % capacity
	_frame_sample_count = mini(_frame_sample_count + 1, capacity)


#region Increment helpers
func count_secondary_mount_evaluated() -> void:
	if not enabled:
		return
	secondary_mounts_evaluated += 1
	if secondary_mounts_evaluated > peak_secondary_mounts_evaluated:
		peak_secondary_mounts_evaluated = secondary_mounts_evaluated


func count_secondary_mount_ready() -> void:
	if not enabled:
		return
	secondary_mounts_ready += 1


func count_secondary_mount_fired() -> void:
	if not enabled:
		return
	secondary_mounts_fired += 1


func count_group_rebuild_requested() -> void:
	if not enabled:
		return
	gunnery_group_rebuilds_requested += 1


func count_group_rebuild_changed() -> void:
	if not enabled:
		return
	gunnery_group_rebuilds_changed += 1


func count_lead_solve() -> void:
	if not enabled:
		return
	gunnery_lead_solves += 1


func count_accuracy_solve() -> void:
	if not enabled:
		return
	gunnery_accuracy_solves += 1


func count_line_of_fire_check() -> void:
	if not enabled:
		return
	line_of_fire_checks += 1


func count_candidate_mount_evaluations(amount: int) -> void:
	if not enabled:
		return
	candidate_mount_evaluations += maxi(amount, 0)


## Accumulates across every battery that reports in one frame, so the totals
## describe the whole battle rather than whichever ship reported last.
func add_secondary_structure(ships: int, mounts: int) -> void:
	if not enabled:
		return
	secondary_ships += maxi(ships, 0)
	secondary_mounts_total += maxi(mounts, 0)
#endregion


#region Live gauges
func register_projectile(is_secondary: bool) -> void:
	if not enabled:
		return
	active_projectiles += 1
	if is_secondary:
		active_secondary_projectiles += 1
	if active_projectiles > peak_active_projectiles:
		peak_active_projectiles = active_projectiles


func unregister_projectile(is_secondary: bool) -> void:
	if not enabled:
		return
	active_projectiles = maxi(active_projectiles - 1, 0)
	if is_secondary:
		active_secondary_projectiles = maxi(
			active_secondary_projectiles - 1,
			0
		)


func register_trail() -> void:
	if not enabled:
		return
	active_trails += 1
	if active_trails > peak_active_trails:
		peak_active_trails = active_trails


func unregister_trail() -> void:
	if not enabled:
		return
	active_trails = maxi(active_trails - 1, 0)
#endregion


func reset_peaks() -> void:
	peak_active_projectiles = active_projectiles
	peak_active_trails = active_trails
	peak_secondary_mounts_evaluated = 0


## Full reset, including live gauges. Used on battle teardown so a new battle
## never inherits stale counts.
func reset_all() -> void:
	begin_frame()
	active_projectiles = 0
	active_secondary_projectiles = 0
	active_trails = 0
	secondary_ships = 0
	secondary_mounts_total = 0
	peak_active_projectiles = 0
	peak_active_trails = 0
	peak_secondary_mounts_evaluated = 0
	_frame_sample_head = 0
	_frame_sample_count = 0


func make_snapshot() -> BattlePerformanceSnapshot:
	var snapshot := BattlePerformanceSnapshot.new()
	snapshot.fps = Engine.get_frames_per_second()
	snapshot.process_time_ms = Performance.get_monitor(
		Performance.TIME_PROCESS
	) * 1000.0
	snapshot.physics_time_ms = Performance.get_monitor(
		Performance.TIME_PHYSICS_PROCESS
	) * 1000.0
	snapshot.draw_calls = int(Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME
	))
	snapshot.rendered_objects = int(Performance.get_monitor(
		Performance.RENDER_TOTAL_OBJECTS_IN_FRAME
	))
	snapshot.node_count = int(Performance.get_monitor(
		Performance.OBJECT_NODE_COUNT
	))
	snapshot.object_count = int(Performance.get_monitor(
		Performance.OBJECT_COUNT
	))
	snapshot.active_projectiles = active_projectiles
	snapshot.active_secondary_projectiles = active_secondary_projectiles
	snapshot.active_trails = active_trails
	snapshot.peak_active_projectiles = peak_active_projectiles
	snapshot.peak_active_trails = peak_active_trails
	snapshot.secondary_ships = secondary_ships
	snapshot.secondary_mounts_total = secondary_mounts_total
	snapshot.secondary_mounts_evaluated = secondary_mounts_evaluated
	snapshot.secondary_mounts_ready = secondary_mounts_ready
	snapshot.secondary_mounts_fired = secondary_mounts_fired
	snapshot.group_rebuilds_requested = gunnery_group_rebuilds_requested
	snapshot.group_rebuilds_changed = gunnery_group_rebuilds_changed
	snapshot.lead_solves = gunnery_lead_solves
	snapshot.accuracy_solves = gunnery_accuracy_solves
	snapshot.line_of_fire_checks = line_of_fire_checks
	snapshot.candidate_mount_evaluations = candidate_mount_evaluations
	_fill_frame_statistics(snapshot)
	return snapshot


## Copies and sorts the ring buffer once per snapshot, not per frame.
func _fill_frame_statistics(snapshot: BattlePerformanceSnapshot) -> void:
	if _frame_sample_count <= 0:
		return
	var samples := PackedFloat32Array()
	samples.resize(_frame_sample_count)
	var capacity := _frame_times_ms.size()
	var start := (_frame_sample_head - _frame_sample_count + capacity) % capacity
	var total := 0.0
	var maximum := 0.0
	for index in _frame_sample_count:
		var value := _frame_times_ms[(start + index) % capacity]
		samples[index] = value
		total += value
		maximum = maxf(maximum, value)
	snapshot.maximum_frame_time_ms = maximum
	var average_ms := total / float(_frame_sample_count)
	snapshot.average_fps = 1000.0 / average_ms if average_ms > 0.0 else 0.0
	snapshot.minimum_fps = 1000.0 / maximum if maximum > 0.0 else 0.0
	var sorted := samples.duplicate()
	sorted.sort()
	# 1% low: the mean of the slowest 1% of frames, which is what a player
	# perceives as a hitch. Falls back to the single worst frame.
	var worst_count := maxi(1, int(float(_frame_sample_count) * 0.01))
	var worst_total := 0.0
	for index in worst_count:
		worst_total += sorted[_frame_sample_count - 1 - index]
	var worst_average := worst_total / float(worst_count)
	snapshot.one_percent_low_fps = 1000.0 / worst_average \
		if worst_average > 0.0 else 0.0


func _get_sample_capacity() -> int:
	return clampi(
		int(_sample_window_sec * float(Engine.get_frames_per_second())) \
			if Engine.get_frames_per_second() > 0 \
			else int(_sample_window_sec * 60.0),
		60,
		FRAME_SAMPLE_CAPACITY
	)
