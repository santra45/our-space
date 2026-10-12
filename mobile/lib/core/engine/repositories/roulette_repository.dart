import 'dart:async';

import '../../../models/date_idea_record.dart';
import '../data/web_data.dart';
import '../storage/tables.dart';
import '../storage/vault_store.dart';
import '../vault/vault_service.dart';

DateIdea? findDateIdea(Object? id) {
  for (final idea in defaultDateIdeas) {
    if (idea.id == id) return idea;
  }
  return null;
}

List<DateIdea> dateIdeasIn(String categoryId) =>
    categoryId == 'all' ? defaultDateIdeas : defaultDateIdeas.where((idea) => idea.category == categoryId).toList();

bool isDateIdeaCategory(Object? id) => dateIdeaCategories.any((category) => category.id == id);

class RouletteRepository {
  RouletteRepository({required this.store, required this.vault});

  final VaultStore store;
  final VaultService vault;

  Future<RouletteStateRecord?> current() async {
    final key = vault.key;
    if (key == null) return null;
    final row = await store.getRow(dateIdeasTable, rouletteStateId);
    if (row == null || row['deleted'] == true) return null;
    Map<String, Object?> plain;
    try {
      plain = await store.getDecrypted(dateIdeasTable, rouletteStateId, key) ?? const {};
    } catch (_) {
      return null;
    }
    if (plain.isEmpty || plain['_headerTampered'] == true || plain['deleted'] == true) return null;
    final record = RouletteStateRecord(Map<String, Object?>.fromEntries(
      plain.entries.where((entry) => !entry.key.startsWith('_')),
    ));
    if (findDateIdea(record.ideaId) == null) return null;
    return record;
  }

  Stream<RouletteStateRecord?> watch() {
    late StreamController<RouletteStateRecord?> controller;
    StreamSubscription<void>? subscription;
    Future<void> refresh() async {
      final value = await current();
      if (!controller.isClosed) controller.add(value);
    }

    void onVault() => unawaited(refresh());
    controller = StreamController<RouletteStateRecord?>(
      onListen: () {
        subscription = store.watchTable(dateIdeasTable).listen((_) => unawaited(refresh()));
        vault.addListener(onVault);
      },
      onCancel: () async {
        vault.removeListener(onVault);
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<Row?> persist({required String ideaId, required String category, required bool revealed}) async {
    final key = vault.key;
    if (key == null) return null;
    try {
      return await store.putEncrypted(
        dateIdeasTable,
        {
          'id': rouletteStateId,
          'ideaId': ideaId,
          'category': category,
          'revealed': revealed,
          'updatedAt': store.clock.next(),
          'deleted': false,
        },
        key,
      );
    } catch (_) {
      return null;
    }
  }
}
