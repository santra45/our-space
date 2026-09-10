/**
 * src/App.jsx
 * Main Application Root with tabs, ambient animations, and zero-knowledge providers
 */
import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { VaultProvider, useVault } from './context/VaultContext';
import { SyncProvider } from './context/SyncContext';
import Header from './components/layout/Header';
import BottomNav from './components/layout/BottomNav';
import LockScreen from './components/layout/LockScreen';
import AmbientParticles from './components/common/AmbientParticles';
import ErrorBoundary from './components/common/ErrorBoundary';
import MilestoneTracker from './components/countdown/MilestoneTracker';
import PolaroidWall from './components/polaroids/PolaroidWall';
import DateRoulette from './components/scratchoff/DateRoulette';
import SecretCapsule from './components/capsule/SecretCapsule';
import BucketList from './components/bucketlist/BucketList';
import SyncHubModal from './components/sync/SyncHubModal';
import DailyQuestion from './components/daily/DailyQuestion';

function AppContent() {
  const { isUnlocked } = useVault();
  const [activeTab, setActiveTab] = useState('countdown');
  const [isSyncModalOpen, setIsSyncModalOpen] = useState(false);

  if (!isUnlocked) {
    return (
      <div className="relative min-h-screen">
        <AmbientParticles />
        <LockScreen />
      </div>
    );
  }

  return (
    <div className="relative min-h-screen flex flex-col justify-between">
      {/* Background Floating Hearts & Sparkles */}
      <AmbientParticles />

      {/* Mobile Top Header with Live Sync Status */}
      <Header onOpenSync={() => setIsSyncModalOpen(true)} />

      {/* Main Tab Content Viewport */}
      <main className="flex-1 max-w-md w-full mx-auto px-4 py-4 pb-safe relative z-10">
        <AnimatePresence mode="wait">
          <motion.div
            key={activeTab}
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -12 }}
            transition={{ duration: 0.22, ease: 'easeOut' }}
          >
            {/*
              Per-tab boundary, keyed on the tab. A crash in one screen must not
              take the header and the nav down with it - with those still on
              screen the user can simply move to another tab, and the key means
              coming back re-mounts it cleanly rather than showing a stale error.
            */}
            <ErrorBoundary key={`boundary-${activeTab}`}>
              {/*
                The daily question rides on the landing tab rather than taking a
                sixth slot in the nav. A daily habit cannot live behind
                navigation - this way it is simply the first thing on screen,
                every time.
              */}
              {activeTab === 'countdown' && (
                <>
                  <DailyQuestion />
                  <MilestoneTracker />
                </>
              )}
              {activeTab === 'polaroids' && <PolaroidWall />}
              {activeTab === 'roulette' && <DateRoulette />}
              {activeTab === 'capsule' && <SecretCapsule />}
              {activeTab === 'bucketlist' && <BucketList />}
            </ErrorBoundary>
          </motion.div>
        </AnimatePresence>
      </main>

      {/* Mobile Thumb Bottom Navigation */}
      <BottomNav activeTab={activeTab} onSelectTab={setActiveTab} />

      {/* Direct P2P WebRTC Pairing & Backup Modal */}
      <SyncHubModal
        isOpen={isSyncModalOpen}
        onClose={() => setIsSyncModalOpen(false)}
      />
    </div>
  );
}

export function App() {
  return (
    // Outermost net. The per-tab boundary handles the common case; this one is
    // for a crash in a provider, the header, the nav or the lock screen, where
    // there is no smaller subtree left to fall back to.
    <ErrorBoundary>
      <VaultProvider>
        <SyncProvider>
          <AppContent />
        </SyncProvider>
      </VaultProvider>
    </ErrorBoundary>
  );
}

export default App;
