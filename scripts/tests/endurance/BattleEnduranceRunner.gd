extends RefCounted
class_name BattleEnduranceRunner

const DEFAULT_CHUNK_SIZE := 600


func run(
		tree: SceneTree,
		total_frames: int,
		metrics: BattleEnduranceMetrics,
		services: BattleServices = null,
		chunk_size: int = DEFAULT_CHUNK_SIZE
) -> void:
	var safe_total := maxi(total_frames, 0)
	var safe_chunk := maxi(chunk_size, 1)
	var frame_index := 0
	var started_msec := Time.get_ticks_msec()
	var chunk_index := 0
	while frame_index < safe_total:
		var frame_count := mini(safe_chunk, safe_total - frame_index)
		for _frame in frame_count:
			await tree.physics_frame
		frame_index += frame_count
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
