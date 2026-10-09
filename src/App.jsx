import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { VaultProvider, useVault } from './context/VaultContext';
import { SyncProvider } from './context/SyncContext';
import { PeopleProvider } from './context/PeopleContext';
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
import PeopleSetup from './components/people/PeopleSetup';

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
      <AmbientParticles />

      <Header onOpenSync={() => setIsSyncModalOpen(true)} />

      <main className="flex-1 max-w-md w-full mx-auto px-4 py-4 pb-safe relative z-10">
        <AnimatePresence mode="wait">
          <motion.div
            key={activeTab}
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -12 }}
            transition={{ duration: 0.22, ease: 'easeOut' }}
          >
            <ErrorBoundary key={`boundary-${activeTab}`}>
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

      <BottomNav activeTab={activeTab} onSelectTab={setActiveTab} />

      <SyncHubModal
        isOpen={isSyncModalOpen}
        onClose={() => setIsSyncModalOpen(false)}
      />

      <PeopleSetup />
    </div>
  );
}

export function App() {
  return (
    <ErrorBoundary>
      <VaultProvider>
        <PeopleProvider>
          <SyncProvider>
            <AppContent />
          </SyncProvider>
        </PeopleProvider>
      </VaultProvider>
    </ErrorBoundary>
  );
}

export default App;
