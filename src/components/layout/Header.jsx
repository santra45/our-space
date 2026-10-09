import React, { useState, useEffect } from 'react';
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
import { usePeople } from '../../context/PeopleContext';
import { useHaptics } from '../../hooks/useHaptics';
import { formatLastSeen } from '../../utils/dateHelpers';

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
  const { partnerName, partnerLastActive } = usePeople();
  const { tick, tap } = useHaptics();
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 30000);
    return () => clearInterval(timer);
  }, []);

  const getStatusDisplay = () => {
    if (syncError) {
      return {
        label: 'Sync hiccup',
        color: 'bg-rose-100 text-rose-700 border-rose-200',
        dot: 'bg-rose-500',
        icon: AlertTriangle,
      };
    }

    if (isAuthorized) {
      if (connectionType === 'direct') {
        return {
          label: 'Phone to phone ⚡',
          color: 'bg-emerald-100 text-emerald-700 border-emerald-200',
          dot: 'bg-emerald-500 animate-pulse',
          icon: Zap,
        };
      }
      if (connectionType === 'relayed') {
        return {
          label: 'Via a helper 🛡️',
          color: 'bg-indigo-100 text-indigo-700 border-indigo-200',
          dot: 'bg-indigo-500 animate-pulse',
          icon: Wifi,
        };
      }
      return {
        label: 'Connected 💕',
        color: 'bg-emerald-100 text-emerald-700 border-emerald-200',
        dot: 'bg-emerald-500 animate-pulse',
        icon: HelpCircle,
      };
    }

    if (isHandshaking) {
      return {
        label: 'Checking…',
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
        <div className="flex items-center gap-2 min-w-0">
          <div className="w-8 h-8 rounded-full bg-gradient-to-tr from-blush-400 to-blush-300 flex items-center justify-center text-white shadow-sm shadow-blush-300/50 shrink-0">
            <Heart className="w-4 h-4 fill-white" />
          </div>
          <div className="min-w-0">
            <h2 className="text-sm font-bold text-slate-800 leading-tight truncate">
              {vaultConfig?.coupleNames || 'Our Space'}
            </h2>
            {isAuthorized ? (
              <p className="text-[10px] text-emerald-600 font-medium flex items-center gap-1 leading-tight truncate">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse shrink-0" />
                <span>{partnerName ? `${partnerName} active now 💕` : 'Active together 💕'}</span>
              </p>
            ) : partnerLastActive ? (
              <p className="text-[10px] text-slate-500 font-medium flex items-center gap-1 leading-tight truncate">
                <span className="w-1.5 h-1.5 rounded-full bg-slate-400 shrink-0" />
                <span>
                  {partnerName
                    ? `${partnerName} • ${formatLastSeen(partnerLastActive, now)}`
                    : `Active ${formatLastSeen(partnerLastActive, now)}`}
                </span>
              </p>
            ) : (
              <p className="text-[10px] text-slate-500 font-medium leading-tight">Just for us 💕</p>
            )}
          </div>
        </div>

        <div className="flex items-center gap-2 shrink-0">
          <button
            onClick={() => {
              tick();
              onOpenSync();
            }}
            title={
              syncError
                ? syncError.text
                : partnerLastActive
                  ? `${status.label} • ${partnerName || 'Partner'} active ${formatLastSeen(partnerLastActive, now)}`
                  : status.label
            }
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
            title="Lock Our Space"
            className="w-8 h-8 rounded-full bg-white/80 border border-blush-200 flex items-center justify-center text-slate-500 hover:text-blush-600 hover:bg-blush-50 transition shadow-sm"
          >
            <Lock className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

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
              aria-label="Dismiss"
              className="w-5 h-5 rounded-full bg-rose-100 text-rose-600 flex items-center justify-center shrink-0"
            >
              <X className="w-3 h-3" />
            </button>
          </div>
        </div>
      )}

      {!syncError && syncWarning && (
        <div className="max-w-md mx-auto mt-2">
          <div className="px-3 py-1.5 bg-amber-50 border border-amber-200 text-amber-700 text-[11px] font-semibold rounded-2xl text-center shadow-sm">
            {syncWarning.text}
          </div>
        </div>
      )}

      {lastSyncNotice && (
        <div className="max-w-md mx-auto mt-2 animate-bounce">
          <div className="px-3 py-1.5 bg-blush-500 text-white text-xs font-semibold rounded-full text-center shadow-md shadow-blush-300/40">
            {lastSyncNotice}
          </div>
        </div>
      )}

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
                ? 'A link is asking to connect to the phone below.'
                : 'There is a saved phone here we have not connected to before.'}
            </p>

            <p className="mt-2 px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl font-mono text-xs font-bold text-slate-700 break-all">
              {pendingInvite.peerId}
            </p>

            <div className="mt-3 p-3 rounded-2xl bg-amber-50 border border-amber-200">
              <p className="text-[11px] text-amber-800 leading-relaxed">
                Only connect if you know who sent you this link.
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
