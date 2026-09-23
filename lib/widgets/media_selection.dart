/// Selection state for media lists (gallery, timeline, ...).
class MediaSelection {
  final Set<String> _keys = {};

  int get length => _keys.length;
  bool get isEmpty => _keys.isEmpty;
  bool get isNotEmpty => _keys.isNotEmpty;

  bool contains(String key) => _keys.contains(key);

  void add(String key) => _keys.add(key);

  void toggle(String key) {
    if (!_keys.remove(key)) _keys.add(key);
  }

  void clear() => _keys.clear();

  void selectAll(Iterable<String> keys) {
    _keys
      ..clear()
      ..addAll(keys);
  }

  bool allSelected(Iterable<String> keys) {
    var any = false;
    for (final key in keys) {
      any = true;
      if (!_keys.contains(key)) return false;
    }
    return any;
  }

  List<T> resolve<T>(Iterable<T> items, String Function(T item) keyOf) {
    return [
      for (final item in items)
        if (_keys.contains(keyOf(item))) item,
    ];
  }
}
