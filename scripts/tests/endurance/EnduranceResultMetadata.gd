extends RefCounted
class_name EnduranceResultMetadata


static func validate(
		total_requested_frames: int,
		total_executed_frames: int,
		chunk_size_frames: int,
		combat_chunk_count: int,
		captured_chunk_count: int
) -> PackedStringArray:
	var failures := PackedStringArray()
	var expected_chunks := ceili(
		float(total_executed_frames)
		/ float(maxi(chunk_size_frames, 1))
	)
	if combat_chunk_count != expected_chunks:
		failures.append(
			"Captured combat chunk count does not match executed frames."
		)
	if captured_chunk_count != combat_chunk_count:
		failures.append("Combat sample count does not match chunk metadata.")
	if total_executed_frames != total_requested_frames:
		failures.append("Endurance runner did not execute all requested frames.")
	return failures


static func build_summary(
		profile_name: StringName,
		seed: int,
		total_requested_frames: int,
		total_executed_frames: int,
		chunk_size_frames: int,
		captured_chunk_count: int,
		combat_chunk_count: int,
		cleanup_chunk_count: int,
		initial_snapshot_count: int,
		final_snapshot_count: int,
		warmup_frames: int,
		cleanup_frames: int
) -> Dictionary:
	return {
		"profile_name": profile_name,
		"seed": seed,
		"total_requested_frames": total_requested_frames,
		"total_executed_frames": total_executed_frames,
		"chunk_size_frames": chunk_size_frames,
		"captured_chunk_count": captured_chunk_count,
		"combat_chunk_count": combat_chunk_count,
		"cleanup_chunk_count": cleanup_chunk_count,
		"initial_snapshot_count": initial_snapshot_count,
		"final_snapshot_count": final_snapshot_count,
		"warmup_frames": warmup_frames,
		"cleanup_frames": cleanup_frames,
	}
