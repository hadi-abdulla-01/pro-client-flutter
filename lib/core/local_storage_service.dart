import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists which notification IDs the current device has marked as read.
class LocalStorageService {
  static const String _readNotificationsKey = 'read_notification_ids';

  Future<SharedPreferences> get _prefs async =>
      await SharedPreferences.getInstance();

  Future<Set<String>> getReadNotificationIds() async {
    final p = await _prefs;
    final List<String> ids = p.getStringList(_readNotificationsKey) ?? [];
    return Set<String>.from(ids);
  }

  Future<void> saveReadNotificationIds(Set<String> ids) async {
    final p = await _prefs;
    await p.setStringList(_readNotificationsKey, ids.toList());
  }
}

final localStorageProvider = Provider<LocalStorageService>(
  (ref) => LocalStorageService(),
);

final readIdsProvider = StateNotifierProvider<ReadIdsNotifier, Set<String>>((
  ref,
) {
  final storage = ref.watch(localStorageProvider);
  return ReadIdsNotifier(storage);
});

class ReadIdsNotifier extends StateNotifier<Set<String>> {
  ReadIdsNotifier(this._storage) : super({}) {
    load();
  }

  final LocalStorageService _storage;
  bool _loaded = false;

  Future<void> load() async {
    state = await _storage.getReadNotificationIds();
    _loaded = true;
  }

  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  void add(String id) {
    if (state.contains(id)) return;
    state = {...state, id};
    _storage.saveReadNotificationIds(state);
  }

  void addAll(List<String> ids) {
    final newIds = ids.where((id) => !state.contains(id));
    if (newIds.isEmpty) return;
    state = {...state, ...newIds};
    _storage.saveReadNotificationIds(state);
  }
}
