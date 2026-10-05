/**
 * src/utils/lockScreenMode.js
 * Which form the lock screen opens on, decided from what we actually know.
 *
 * Kept out of LockScreen.jsx so the decision can be tested without React.
 */

/**
 * @param {{
 *   vaultCheckState: 'checking'|'unreadable'|'present'|'absent',
 *   inviteHasSalt: boolean,
 *   installed: boolean,
 * }} facts
 * @returns {'unlock'|'join'|'setup'|null} null while we cannot tell yet.
 */
export function defaultLockScreenMode({ vaultCheckState, inviteHasSalt, installed }) {
  // A phone that has a vault ALWAYS opens on unlock, invite link or not. See
  // LockScreen.jsx for the crafted link this rules out.
  if (vaultCheckState === 'present') return 'unlock';

  // 'checking' and 'unreadable' choose nothing: a vault we cannot see is not a
  // vault that is not there.
  if (vaultCheckState !== 'absent') return null;

  if (inviteHasSalt) return 'join';

  // An installed app with nothing in it almost always belongs to someone who
  // has been here before and lost their space - evicted storage, cleared site
  // data - not someone starting one. Opening on Create invites them to type
  // their usual passphrase into it and end up on a second, separate space.
  return installed ? 'join' : 'setup';
}
