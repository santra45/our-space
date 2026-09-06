/**
 * src/components/layout/Header.jsx
 * Mobile top bar with partner sync status indicator and vault lock button
 */
import React from 'react';
import { Heart, Wifi, WifiOff, Lock, RefreshCw, Share2 } from 'lucide-react';
import { useVault } from '../../context/VaultContext';
import { useSync } from '../../context/SyncContext';
import { useHaptics } from '../../hooks/useHaptics';

export function Header({ onOpenSync, onOpenBackup }) {
  const { vaultConfig, lockVault } = useVault();
  const { isPartnerConnected, syncStatus, lastSyncNotice } = useSync();
  const { tick } = useHaptics();

  const getStatusDisplay = () => {
    if (isPartnerConnected) {
      return {
        label: 'Partner Connected',
        color: 'bg-emerald-100 text-emerald-700 border-emerald-200',
        dot: 'bg-emerald-500 animate-pulse',
        icon: Wifi,
      };
    }
    if (syncStatus.state === 'connecting') {
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

      {/* Sync toast notification if received from partner */}
      {lastSyncNotice && (
        <div className="max-w-md mx-auto mt-2 animate-bounce">
          <div className="px-3 py-1.5 bg-blush-500 text-white text-xs font-semibold rounded-full text-center shadow-md shadow-blush-300/40">
            {lastSyncNotice}
          </div>
        </div>
      )}
    </header>
  );
}

export default Header;
