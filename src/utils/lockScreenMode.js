export function defaultLockScreenMode({ vaultCheckState, inviteHasSalt, installed }) {
  if (vaultCheckState === 'present') return 'unlock';

  if (vaultCheckState !== 'absent') return null;

  if (inviteHasSalt) return 'join';

  return installed ? 'join' : 'setup';
}
