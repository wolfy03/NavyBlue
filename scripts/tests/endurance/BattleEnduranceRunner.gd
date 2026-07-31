extends RefCounted
class_name BattleEnduranceRunner

const DEFAULT_CHUNK_SIZE := EnduranceProfile.DEFAULT_CHUNK_SIZE_FRAMES


func run(
		tree: SceneTree,
		total_frames: int,
		metrics: BattleEnduranceMetrics,
		services: BattleServices = null,
		chunk_size: int = DEFAULT_CHUNK_SIZE
) -> void:
	var safe_total := maxi(total_frames, 0)
	var safe_chunk := maxi(chunk_size, 1)
	metrics.total_requested_frames = safe_total
	metrics.chunk_size_frames = safe_chunk
	var frame_index := 0
	var started_msec := Time.get_ticks_msec()
	var chunk_index := 0
	while frame_index < safe_total:
		var frame_count := mini(safe_chunk, safe_total - frame_index)
		var chunk_started_msec := Time.get_ticks_msec()
		for _frame in frame_count:
			await tree.physics_frame
		metrics.record_chunk_timing(
			frame_count,
			float(Time.get_ticks_msec() - chunk_started_msec)
		)
		frame_index += frame_count
		metrics.total_executed_frames = frame_index
		var elapsed_sec := float(
			Time.get_ticks_msec() - started_msec
		) * 0.001
		metrics.capture_chunk(
			tree,
			chunk_index,
			elapsed_sec,
			services
		)
		chunk_index += 1
	metrics.combat_chunk_count = chunk_index


func wait_frames(tree: SceneTree, frame_count: int) -> void:
	for _frame in maxi(frame_count, 0):
		await tree.physics_frame
