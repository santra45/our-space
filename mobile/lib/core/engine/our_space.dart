import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'crypto/js_compat.dart';
import 'domain/daily_question.dart';
import 'domain/love_bursts.dart';
import 'identity/device_id.dart';
import 'identity/identity_controller.dart';
import 'identity/people.dart';
import 'identity/people_repair.dart';
import 'repositories/bucket_list_repository.dart';
import 'repositories/letters_repository.dart';
import 'repositories/memories_repository.dart';
import 'repositories/milestones_repository.dart';
import 'repositories/roulette_repository.dart';
import 'storage/vault_store.dart';
import 'sync/backup_service.dart';
import 'sync/mailbox.dart';
import 'sync/sync_service.dart';
import 'vault/vault_service.dart';

class OurSpace {
  OurSpace._({
    required this.store,
    required this.device,
    required this.vault,
    required this.peopleService,
    required this.repair,
    required this.identity,
    required this.memories,
    required this.milestones,
    required this.letters,
    required this.bucketList,
    required this.roulette,
    required this.dailyQuestion,
    required this.loveBursts,
    required this.mailbox,
    required this.sync,
    required this.backup,
  });

  static Future<OurSpace> open({
    DatabaseFactory? databaseFactory,
    String? databasePath,
    MailboxConfig? mailboxConfig,
    bool useEnvironmentMailbox = true,
    http.Client? httpClient,
    NowFn now = systemNow,
    bool autoSync = true,
  }) async {
    final store = await VaultStore.open(factory: databaseFactory, path: databasePath, now: now);
    final device = DeviceIdentity(store.settings);
    final vault = VaultService(store: store, device: device);
    final peopleService = PeopleService(store: store, settings: store.settings, device: device);
    final dailyQuestion = DailyQuestionService(store: store);
    final repair = PeopleRepair(store: store, people: peopleService, answers: dailyQuestion);
    final identity = IdentityController(store: store, vault: vault, people: peopleService, repair: repair);
    final loveBursts = LoveBurstService(store: store, settings: store.settings, device: device);
    final mailbox = Mailbox(
      store: store,
      config: mailboxConfig ?? (useEnvironmentMailbox ? MailboxConfig.fromEnvironment() : null),
      client: httpClient,
    );
    final sync = SyncService(
      store: store,
      vault: vault,
      identity: identity,
      mailbox: mailbox,
      loveBursts: loveBursts,
      autoSync: autoSync,
    );
    final space = OurSpace._(
      store: store,
      device: device,
      vault: vault,
      peopleService: peopleService,
      repair: repair,
      identity: identity,
      memories: MemoriesRepository(store: store, vault: vault),
      milestones: MilestonesRepository(store: store, vault: vault),
      letters: LettersRepository(store: store, vault: vault),
      bucketList: BucketListRepository(store: store, vault: vault),
      roulette: RouletteRepository(store: store, vault: vault),
      dailyQuestion: dailyQuestion,
      loveBursts: loveBursts,
      mailbox: mailbox,
      sync: sync,
      backup: BackupService(store: store, vault: vault),
    );
    await vault.check();
    return space;
  }

  final VaultStore store;
  final DeviceIdentity device;
  final VaultService vault;
  final PeopleService peopleService;
  final PeopleRepair repair;
  final IdentityController identity;
  final MemoriesRepository memories;
  final MilestonesRepository milestones;
  final LettersRepository letters;
  final BucketListRepository bucketList;
  final RouletteRepository roulette;
  final DailyQuestionService dailyQuestion;
  final LoveBurstService loveBursts;
  final Mailbox mailbox;
  final SyncService sync;
  final BackupService backup;

  Stream<void> watchTable(String table) => store.watchTable(table);

  Future<void> close() async {
    sync.dispose();
    identity.dispose();
    vault.dispose();
    mailbox.close();
    await store.close();
  }
}
