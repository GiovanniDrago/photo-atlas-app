import 'package:flutter_test/flutter_test.dart';
import 'package:photoatlas/models/gallery_entry.dart';
import 'package:photoatlas/models/gallery_upload.dart';
import 'package:photoatlas/models/media_item.dart';
import 'package:photoatlas/services/gallery_actions_service.dart';

GalleryEntry entry(String name) {
  return GalleryEntry(
    cloud: MediaItem.fromJson({
      'id': 'id-$name',
      'source_id': '22222222-2222-2222-2222-222222222222',
      'external_key': 'asset-$name',
      'name': name,
      'media_type': 'image',
      'metadata_status': 'full',
      'backup_status': 'none',
      'has_gps': false,
      'source_kind': 'local',
    }),
  );
}

void main() {
  test('records the current file, completed items and failures', () {
    var state = GalleryUploadState(
      label: 'Uploading',
      targets: [entry('a.jpg'), entry('b.jpg'), entry('c.jpg')],
      total: 3,
    );
    expect(state.running, isTrue);
    expect(state.statusAt(0), UploadEntryStatus.current);
    expect(state.statusAt(1), UploadEntryStatus.pending);

    state = state.record(
      const GalleryActionProgress(done: 0, total: 3, currentName: 'a.jpg'),
    );
    expect(state.statusAt(0), UploadEntryStatus.current);

    state = state.record(
      const GalleryActionProgress(done: 1, total: 3, currentName: 'b.jpg'),
    );
    expect(state.statusAt(0), UploadEntryStatus.done);
    expect(state.statusAt(1), UploadEntryStatus.current);
    expect(state.done, 1);

    state = state.record(
      const GalleryActionProgress(
        done: 1,
        total: 3,
        currentName: 'b.jpg',
        failedName: 'b.jpg',
        error: 'boom',
      ),
    );
    expect(state.statusAt(1), UploadEntryStatus.failed);
    expect(state.failures[1], 'boom');

    state = state.record(
      const GalleryActionProgress(done: 2, total: 3, currentName: 'c.jpg'),
    );
    expect(state.statusAt(1), UploadEntryStatus.failed);
    expect(state.statusAt(2), UploadEntryStatus.current);
  });

  test('finish closes the run with the counters', () {
    final state =
        GalleryUploadState(
              label: 'Uploading',
              targets: [entry('a.jpg'), entry('b.jpg')],
              total: 2,
            )
            .record(
              const GalleryActionProgress(
                done: 1,
                total: 2,
                currentName: 'b.jpg',
                failedName: 'b.jpg',
                error: 'nope',
              ),
            )
            .finish(uploaded: 1, failed: 1, cancelled: false);
    expect(state.running, isFalse);
    expect(state.stopping, isFalse);
    expect(state.done, 2);
    expect(state.currentName, isNull);
    expect(state.uploaded, 1);
    expect(state.failed, 1);
    expect(state.cancelled, isFalse);
    expect(state.statusAt(0), UploadEntryStatus.done);
    expect(state.statusAt(1), UploadEntryStatus.failed);
  });

  test('markStopping flags the run and keeps the progress', () {
    final state = GalleryUploadState(
      label: 'Retrying',
      targets: [entry('a.jpg')],
      total: 1,
    ).markStopping();
    expect(state.stopping, isTrue);
    expect(state.running, isTrue);
    expect(state.statusAt(0), UploadEntryStatus.current);
  });

  test('records single-file bytes and clears them on the next item', () {
    var state = GalleryUploadState(
      label: 'Uploading',
      targets: [entry('a.jpg'), entry('b.jpg')],
      total: 2,
    );
    state = state.record(
      const GalleryActionProgress(
        done: 0,
        total: 2,
        currentName: 'a.jpg',
        fileSent: 50,
        fileTotal: 200,
      ),
    );
    expect(state.fileFraction, closeTo(0.25, 0.0001));
    expect(state.overallFraction, closeTo(0.125, 0.0001));

    state = state.record(
      const GalleryActionProgress(done: 1, total: 2, currentName: 'b.jpg'),
    );
    expect(state.fileFraction, isNull);
    expect(state.overallFraction, closeTo(0.5, 0.0001));

    state = state.finish(uploaded: 2, failed: 0, cancelled: false);
    expect(state.fileFraction, isNull);
    expect(state.overallFraction, 1.0);
  });

  test('file progress throttle emits at most one update per percent', () {
    final throttle = FileProgressThrottle();
    expect(
      throttle.shouldEmit(const GalleryActionProgress(done: 0, total: 1)),
      isTrue,
    );
    expect(
      throttle.shouldEmit(
        const GalleryActionProgress(
          done: 0,
          total: 1,
          fileSent: 1,
          fileTotal: 1000,
        ),
      ),
      isFalse,
    );
    expect(
      throttle.shouldEmit(
        const GalleryActionProgress(
          done: 0,
          total: 1,
          fileSent: 10,
          fileTotal: 1000,
        ),
      ),
      isTrue,
    );
    expect(
      throttle.shouldEmit(
        const GalleryActionProgress(
          done: 0,
          total: 1,
          fileSent: 15,
          fileTotal: 1000,
        ),
      ),
      isFalse,
    );
    expect(
      throttle.shouldEmit(
        const GalleryActionProgress(
          done: 0,
          total: 1,
          fileSent: 1000,
          fileTotal: 1000,
        ),
      ),
      isTrue,
    );
    // The next item restarts the window.
    expect(
      throttle.shouldEmit(
        const GalleryActionProgress(
          done: 1,
          total: 2,
          fileSent: 10,
          fileTotal: 1000,
        ),
      ),
      isTrue,
    );
  });

  test('cancelled runs keep the completed count', () {
    final state = GalleryUploadState(
      label: 'Uploading',
      targets: [entry('a.jpg'), entry('b.jpg'), entry('c.jpg')],
      total: 3,
    ).finish(uploaded: 1, failed: 0, cancelled: true);
    expect(state.cancelled, isTrue);
    expect(state.uploaded, 1);
    expect(state.failed, 0);
  });
}
