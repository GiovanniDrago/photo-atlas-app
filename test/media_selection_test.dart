import 'package:flutter_test/flutter_test.dart';
import 'package:photoatlas/widgets/media_selection.dart';

void main() {
  test('toggles keys and reports the count', () {
    final selection = MediaSelection();
    expect(selection.isEmpty, isTrue);
    selection.toggle('a');
    selection.toggle('b');
    expect(selection.length, 2);
    expect(selection.contains('a'), isTrue);
    selection.toggle('a');
    expect(selection.contains('a'), isFalse);
    expect(selection.length, 1);
  });

  test('selects all and clears', () {
    final selection = MediaSelection();
    selection.selectAll(['a', 'b', 'c']);
    expect(selection.allSelected(['a', 'b']), isTrue);
    expect(selection.allSelected(['a', 'z']), isFalse);
    expect(selection.allSelected(const []), isFalse);
    selection.clear();
    expect(selection.isEmpty, isTrue);
  });

  test('resolves the selected items', () {
    final selection = MediaSelection()..toggle('b');
    final resolved = selection.resolve(['a', 'b', 'c'], (value) => value);
    expect(resolved, ['b']);
  });
}
