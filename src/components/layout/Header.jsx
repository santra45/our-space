/**
 * src/components/layout/Header.jsx
 * Mobile top bar with partner sync status indicator and vault lock button.
 *
 * Every indicator here is driven by `isAuthorized`, never by the raw socket
 * state: peerSync reports `handshaking` for a channel that opened but has not
 * proved it holds the vault key, and any stranger who knows our peer id can
 * reach that state. Only a peer that survived the challenge gets a green pill.
 */
import React from 'react';
import { createPortal } from 'react-dom';
import {
  Heart,
  Wifi,
  Lock,
  RefreshCw,
  Share2,
  Zap,
  HelpCircle,
  AlertTriangle,
  ShieldAlert,
  X,
} from 'lucide-react';
import { useVault } from '../../context/VaultContext';
import { useSync } from '../../context/SyncContext';
import { useHaptics } from '../../hooks/useHaptics';

export function Header({ onOpenSync }) {
  const { vaultConfig, lockVault } = useVault();
  const {
    isAuthorized,
    isHandshaking,
    isConnecting,
    syncStatus,
    lastSyncNotice,
    syncWarning,
    syncError,
    clearSyncError,
    connectionType,
    pendingInvite,
    confirmPendingInvite,
    declinePendingInvite,
  } = useSync();
  const { tick, tap } = useHaptics();

  const getStatusDisplay = () => {
    // A fatal problem outranks everything: it is the only place the user learns
    // that the passphrases differ or that ICE never found a route.
    if (syncError) {
      return {
        label: 'Sync Issue',
        color: 'bg-rose-100 text-rose-700 border-rose-200',
        dot: 'bg-rose-500',
        icon: AlertTriangle,
      };
    }

    if (isAuthorized) {
      if (connectionType === 'direct') {
        return {
          label: 'Direct P2P ⚡',
          color: 'bg-emerald-100 text-emerald-700 border-emerald-200',
          dot: 'bg-emerald-500 animate-pulse',
          icon: Zap,
        };
      }
      if (connectionType === 'relayed') {
        return {
          label: 'Relayed 🛡️',
          color: 'bg-indigo-100 text-indigo-700 border-indigo-200',
          dot: 'bg-indigo-500 animate-pulse',
          icon: Wifi,
        };
      }
      // X3: the route genuinely is not known yet. Say so instead of guessing.
      return {
        label: 'Route unknown',
        color: 'bg-emerald-100 text-emerald-700 border-emerald-200',
        dot: 'bg-emerald-500 animate-pulse',
        icon: HelpCircle,
      };
    }

    // Channel open, identity NOT proven. Deliberately not green.
    if (isHandshaking) {
      return {
        label: 'Verifying...',
        color: 'bg-amber-100 text-amber-700 border-amber-200',
        dot: 'bg-amber-500 animate-ping',
        icon: ShieldAlert,
      };
    }

    if (isConnecting) {
      return {
        label: 'Pairing...',
        color: 'bg-amber-100 text-amber-700 border-amber-200',
        dot: 'bg-amber-500 animate-ping',
        icon: RefreshCw,
      };
    }

    return {
      label: 'Tap to Pair',
      color: 'bg-white/80 text-blush-600 border-blush-200',
      dot: 'bg-blush-400',
      icon: Share2,
    };
  };

  const status = getStatusDisplay();
  const StatusIcon = status.icon;

  return (
    <header className="sticky top-0 z-30 pt-safe px-4 py-3 backdrop-blur-md bg-blush-50/70 border-b border-blush-100/50">
      <div className="max-w-md mx-auto flex items-center justify-between">
        {/* Left: Couple Title */}
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-full bg-gradient-to-tr from-blush-400 to-blush-300 flex items-center justify-center text-white shadow-sm shadow-blush-300/50">
            <Heart className="w-4 h-4 fill-white" />
          </div>
          <div>
            <h2 className="text-sm font-bold text-slate-800 leading-tight">
              {vaultConfig?.coupleNames || 'Our Space'}
            </h2>
            <p className="text-[10px] text-slate-500 font-medium">Zero-Knowledge Vault</p>
          </div>
        </div>

        {/* Right: Sync Status Pill & Lock Button */}
        <div className="flex items-center gap-2">
          <button
            onClick={() => {
              tick();
              onOpenSync();
            }}
            title={syncError ? syncError.text : status.label}
            className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold border transition shadow-sm ${status.color}`}
          >
            <span className={`w-2 h-2 rounded-full ${status.dot}`} />
            <StatusIcon className="w-3.5 h-3.5" />
            <span className="hidden xs:inline">{status.label}</span>
          </button>

          <button
            onClick={() => {
              tick();
              lockVault();
            }}
            title="Lock Vault"
            className="w-8 h-8 rounded-full bg-white/80 border border-blush-200 flex items-center justify-center text-slate-500 hover:text-blush-600 hover:bg-blush-50 transition shadow-sm"
          >
            <Lock className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      {/* X4: fatal sync problem, with the actionable wording peerSync supplied */}
      {syncError && (
        <div className="max-w-md mx-auto mt-2">
          <div className="flex items-start gap-2 px-3 py-2 bg-rose-50 border border-rose-200 rounded-2xl shadow-sm">
            <AlertTriangle className="w-3.5 h-3.5 text-rose-500 mt-0.5 shrink-0" />
            <div className="flex-1 min-w-0">
              <p className="text-[11px] font-bold text-rose-700 leading-tight">{syncError.text}</p>
              <button
                type="button"
                onClick={() => {
                  tick();
                  onOpenSync();
                }}
                className="text-[10px] font-bold text-rose-600 underline mt-1"
              >
                Open the Pair &amp; Sync hub
              </button>
            </div>
            <button
              type="button"
              onClick={() => {
                tick();
                clearSyncError();
              }}
              aria-label="Dismiss sync error"
              className="w-5 h-5 rounded-full bg-rose-100 text-rose-600 flex items-center justify-center shrink-0"
            >
              <X className="w-3 h-3" />
            </button>
          </div>
        </div>
      )}

      {/* Non-fatal problem. Carries the live state, so it must never look fatal. */}
      {!syncError && syncWarning && (
        <div className="max-w-md mx-auto mt-2">
          <div className="px-3 py-1.5 bg-amber-50 border border-amber-200 text-amber-700 text-[11px] font-semibold rounded-2xl text-center shadow-sm">
            {syncWarning.text}
          </div>
        </div>
      )}

      {/* Sync progress notice received from partner */}
      {lastSyncNotice && (
        <div className="max-w-md mx-auto mt-2 animate-bounce">
          <div className="px-3 py-1.5 bg-blush-500 text-white text-xs font-semibold rounded-full text-center shadow-md shadow-blush-300/40">
            {lastSyncNotice}
          </div>
        </div>
      )}

      {/* X6: a peer id from a link is not consent to dial it.
          Portalled to <body>: this <header> sets backdrop-blur, which makes it a
          containing block for fixed descendants, so an overlay rendered inline
          would be trapped inside the header strip and painted under the z-40
          bottom nav. */}
      {pendingInvite &&
        createPortal(
          <div className="fixed inset-0 z-[80] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
          <div className="w-full max-w-sm bg-white rounded-3xl p-5 shadow-2xl border border-blush-100">
            <div className="flex items-center gap-2 mb-3">
              <div className="w-9 h-9 rounded-full bg-amber-100 text-amber-600 flex items-center justify-center shrink-0">
                <ShieldAlert className="w-4 h-4" />
              </div>
              <h3 className="text-base font-bold text-slate-800">Connect to this device?</h3>
            </div>

            <p className="text-xs text-slate-600 leading-relaxed">
              {pendingInvite.fromLink
                ? 'A pairing link asked this app to connect to the device below.'
                : 'This app has a saved partner device it has not connected to before.'}
            </p>

            <p className="mt-2 px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl font-mono text-xs font-bold text-slate-700 break-all">
              {pendingInvite.peerId}
            </p>

            <div className="mt-3 p-3 rounded-2xl bg-amber-50 border border-amber-200">
              <p className="text-[11px] text-amber-800 leading-relaxed">
                <strong>Connecting reveals your IP address to that device.</strong> A direct
                peer-to-peer connection exchanges network candidates, which include your phone&apos;s
                local and public IP. Only continue if you know who sent you this link and recognise
                the code above from their screen.
              </p>
            </div>

            <div className="mt-4 grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => {
                  tick();
                  declinePendingInvite();
                }}
                className="py-2.5 rounded-2xl border border-slate-200 text-xs font-bold text-slate-600 hover:bg-slate-50"
              >
                Not now
              </button>
              <button
                type="button"
                onClick={() => {
                  tap();
                  confirmPendingInvite();
                }}
                className="py-2.5 rounded-2xl bg-blush-500 text-white text-xs font-bold shadow-sm shadow-blush-300/50 hover:bg-blush-600"
              >
                Connect
              </button>
            </div>
          </div>
          </div>,
          document.body
        )}
    </header>
  );
}

export default Header;
