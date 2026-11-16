import '../crypto/derived_ids.dart';
import '../identity/identity_controller.dart';
import '../p2p/peer_hub.dart';
import '../vault/vault_service.dart';
import 'mailbox.dart';

class MailboxPartnerCodes implements PartnerCodes {
  MailboxPartnerCodes({required this.mailbox, required this.vault, required this.identity});

  final Mailbox mailbox;
  final VaultService vault;
  final IdentityController identity;

  @override
  Future<bool> leave(String myCode) =>
      mailbox.leavePeerCode(key: vault.key, ownerId: identity.myOwnerId, code: myCode);

  @override
  Future<List<String>> find() async {
    final key = vault.key;
    if (key == null) return const [];
    final mine = identity.myOwnerId;
    final found = <PeerCode>[];
    for (final slot in derivePersonSlots(key)) {
      if (slot == mine) continue;
      final code = await mailbox.readPeerCode(key: key, ownerId: slot);
      if (code != null) found.add(code);
    }
    found.sort((a, b) => b.at.compareTo(a.at));
    return [for (final code in found) code.peerId];
  }
}
