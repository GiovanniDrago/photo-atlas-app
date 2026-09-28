package dev.giovannidrago.photoatlas.studio.domain.gallery

import dev.giovannidrago.photoatlas.studio.data.remote.MediaItemDto

/** What the delete dialog can remove, ported from the Flutter options. */
data class DeleteOptions(
	val cloud: Boolean,
	val local: Boolean,
)

/** API batches planned for a deletion (pure, tested). */
data class DeletePlan(
	/** kDrive trash + index row dropped (nothing left on the device). */
	val dropIds: List<String> = emptyList(),
	/** kDrive trash, index row kept (a device copy survives). */
	val resetIds: List<String> = emptyList(),
	/** Index row dropped although it was never uploaded. */
	val indexOnlyIds: List<String> = emptyList(),
) {
	val isEmpty: Boolean get() = dropIds.isEmpty() && resetIds.isEmpty() && indexOnlyIds.isEmpty()
}

/**
 * Classifies the selected entries exactly like the Flutter gallery:
 * - cloud + (device copy gone or absent) → drop the row;
 * - cloud + device copy still there → reset the upload state;
 * - device copy gone and never uploaded → drop the index row only.
 */
fun planDelete(
	entries: List<GalleryEntry>,
	cloud: Boolean,
	local: Boolean,
	deletedLocalIds: Set<Long>,
): DeletePlan {
	val drop = mutableListOf<String>()
	val reset = mutableListOf<String>()
	val indexOnly = mutableListOf<String>()
	for (entry in entries) {
		val item: MediaItemDto = entry.cloud ?: continue
		val localGone = local && entry.hasLocal && deletedLocalIds.contains(entry.local?.id)
		if (cloud && entry.canDeleteCloud) {
			if (localGone || !entry.hasLocal) {
				drop += item.id
			} else {
				reset += item.id
			}
		} else if (localGone && !entry.isUploaded) {
			indexOnly += item.id
		}
	}
	return DeletePlan(dropIds = drop, resetIds = reset, indexOnlyIds = indexOnly)
}
