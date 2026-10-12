import { createInterface } from 'node:readline';

import { FakeConn, FakeVaultStore, Side, clean, crypto, fromBase64, toBase64 } from './web_peer_kit.mjs';

const out = (message) => process.stdout.write(`${JSON.stringify(message)}\n`);

let side = null;
let conn = null;

async function handle(message) {
  switch (message.cmd) {
    case 'init': {
      const key = await crypto.importVaultKeyFromBits(fromBase64(message.key));
      const store = new FakeVaultStore();
      await store.seedWire(message.seed);
      side = new Side('web', message.myId, key, store);
      side.manager.on('status', (status) => {
        out({ status: clean(status) });
        if (status.state === 'authorized' && message.config) {
          side.run(() => side.manager.syncVaultConfig(message.config));
        }
      });
      side.manager.on('data-updated', (payload) => out({ event: 'data-updated', ...clean(payload) }));
      side.manager.on('config-synced', (payload) => out({ event: 'config-synced', ...clean(payload) }));
      conn = new FakeConn(side, message.partnerId, (bytes) => out({ frame: toBase64(bytes) }));
      conn.onClosed = () => out({ closed: true });
      const initiator = message.role === 'initiator';
      side.run(() => {
        if (initiator) side.manager.dialingPeerId = message.partnerId;
        side.manager._setupConnection(conn, initiator);
      });
      out({ ready: true });
      break;
    }
    case 'open':
      conn.openNow();
      break;
    case 'frame':
      side.run(() => conn.receive(fromBase64(message.frame).buffer));
      break;
    case 'remote-close':
      side.run(() => conn.close());
      break;
    case 'sync':
      out({ synced: await side.run(() => side.manager.syncNow()) });
      break;
    case 'broadcast': {
      const row = {};
      for (const [field, value] of Object.entries(message.row)) {
        if (field === 'imageBlobBase64') continue;
        row[field] = value;
      }
      if (typeof message.row.imageBlobBase64 === 'string') row.imageBlob = fromBase64(message.row.imageBlobBase64);
      await side.store.seed(message.table, row);
      out({ broadcast: await side.run(() => side.manager.broadcastLiveRecord(message.table, row)) });
      break;
    }
    case 'dump':
      out({ dump: await side.store.dump() });
      break;
    case 'exit':
      if (side) side.run(() => side.manager.destroy());
      setTimeout(() => process.exit(0), 20);
      break;
    default:
      out({ error: `unknown command ${message.cmd}` });
  }
}

createInterface({ input: process.stdin }).on('line', (line) => {
  if (!line.trim()) return;
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    out({ error: 'bad line' });
    return;
  }
  handle(message).catch((err) => out({ error: String((err && err.stack) || err) }));
});

out({ hello: true });
