/**
 * Automated Verification Script for Web Crypto AES-GCM & PBKDF2
 */
import {
  generateSalt,
  deriveKeyFromPassphrase,
  encryptText,
  decryptText,
  encryptJSON,
  decryptJSON,
  encryptBlob,
  decryptBlob,
  generateSecureNonce,
  createEncryptedBackup,
  decryptBackupContainer,
  MIN_PASSPHRASE_LENGTH,
} from './src/services/crypto.js';

async function runTests() {
  console.log('--- Starting Web Crypto Verification Suite ---');

  const passphrase = 'my-super-secret-couple-passphrase-2026';
  const salt = generateSalt();
  console.log('✔ Generated Vault Salt:', salt);

  // 1. Minimum Passphrase Length Enforcement
  try {
    await deriveKeyFromPassphrase('short123', salt);
    throw new Error('SECURITY FAILURE: Passphrase under 16 chars was accepted!');
  } catch (err) {
    if (err.message.includes('SECURITY FAILURE')) throw err;
    console.log(`✔ Security Validation Passed: Passphrase shorter than ${MIN_PASSPHRASE_LENGTH} chars was rejected.`);
  }

  // 2. Cryptographic Nonce Generation
  const nonce1 = generateSecureNonce(16);
  const nonce2 = generateSecureNonce(16);
  if (!nonce1 || !nonce2 || nonce1 === nonce2) {
    throw new Error('Nonce generation collision or invalid!');
  }
  console.log('✔ Cryptographically secure random nonces generated successfully.');

  // 3. Derive Key
  const key1 = await deriveKeyFromPassphrase(passphrase, salt);
  const key2 = await deriveKeyFromPassphrase(passphrase, salt);
  console.log('✔ PBKDF2 Key Derived Successfully');

  // 4. Encrypt and Decrypt Text
  const message = 'I love you to the moon and back 💕';
  const { ciphertext, iv } = await encryptText(message, key1);
  console.log('✔ Encrypted Text (IV length = 12 bytes, Ciphertext generated)');

  const decrypted = await decryptText(ciphertext, iv, key2);
  if (decrypted !== message) {
    throw new Error(`Decrypted text mismatch! Expected "${message}", got "${decrypted}"`);
  }
  console.log('✔ Decrypted Text matches perfectly:', decrypted);

  // 5. Encrypt and Decrypt JSON
  const memoryObj = {
    caption: 'Our first sunset in Bali 🌅',
    date: '2026-06-15',
    tags: ['beach', 'sunset', 'love'],
  };
  const jsonEncrypted = await encryptJSON(memoryObj, key1);
  const jsonDecrypted = await decryptJSON(jsonEncrypted.ciphertext, jsonEncrypted.iv, key2);
  if (JSON.stringify(memoryObj) !== JSON.stringify(jsonDecrypted)) {
    throw new Error('JSON roundtrip mismatch!');
  }
  console.log('✔ JSON Object Encrypted and Decrypted successfully:', jsonDecrypted);

  // 6. Encrypt and Decrypt Binary Blob
  const rawBytes = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 3, 4, 5, 255]); // Mock image header
  const mockBlob = new Blob([rawBytes], { type: 'image/webp' });
  const packedEncrypted = await encryptBlob(mockBlob, key1);

  const decryptedBlob = await decryptBlob(packedEncrypted, key2, 'image/webp');
  const decryptedBytes = new Uint8Array(await decryptedBlob.arrayBuffer());

  if (decryptedBytes.length !== rawBytes.length) {
    throw new Error('Decrypted blob length mismatch!');
  }
  for (let i = 0; i < rawBytes.length; i++) {
    if (decryptedBytes[i] !== rawBytes[i]) {
      throw new Error(`Byte mismatch at index ${i}`);
    }
  }
  console.log('✔ Binary Image Blob encrypted, packed with 12-byte IV, and decrypted perfectly!');

  // 7. Tamper / Authentication Tag Verification Test
  try {
    const tamperedCipher = ciphertext.substring(0, ciphertext.length - 4) + 'AAAA';
    await decryptText(tamperedCipher, iv, key1);
    throw new Error('SECURITY FAILURE: Tampered ciphertext was accepted!');
  } catch (err) {
    if (err.message.includes('SECURITY FAILURE')) throw err;
    console.log('✔ Security Validation Passed: Tampered ciphertext was rejected by AES-GCM auth tag.');
  }

  // 8. Wrong Passphrase Test
  const wrongKey = await deriveKeyFromPassphrase('wrong-passphrase-with-enough-chars', salt);
  try {
    await decryptText(ciphertext, iv, wrongKey);
    throw new Error('SECURITY FAILURE: Decryption succeeded with wrong passphrase!');
  } catch (err) {
    if (err.message.includes('SECURITY FAILURE')) throw err;
    console.log('✔ Security Validation Passed: Incorrect passphrase was rejected.');
  }

  // 9. Single-Container Encrypted Backup Export & Import Test
  const mockDatabaseData = {
    tables: {
      memories: [{ id: 'mem-1', date: '2026-06-15', captionCipher: 'abc', captionIv: 'def' }],
      milestones: [{ id: 'ms-1', titleCipher: 'ghi', titleIv: 'jkl' }],
    },
  };
  const encryptedBackup = await createEncryptedBackup(mockDatabaseData, passphrase);
  if (
    encryptedBackup.magic !== 'OUR_SPACE_ENCRYPTED_VAULT_V1' ||
    !encryptedBackup.salt ||
    !encryptedBackup.iv ||
    !encryptedBackup.ciphertext
  ) {
    throw new Error('Encrypted backup container missing required fields!');
  }
  console.log('✔ Single-container encrypted backup container created with fresh salt and IV.');

  const restoredData = await decryptBackupContainer(encryptedBackup, passphrase);
  if (JSON.stringify(restoredData) !== JSON.stringify(mockDatabaseData)) {
    throw new Error('Restored backup data does not match original mock data!');
  }
  console.log('✔ Backup decrypted and restored cleanly with correct passphrase.');

  // 10. Tampered Backup Container Test
  try {
    const tamperedBackup = {
      ...encryptedBackup,
      ciphertext: encryptedBackup.ciphertext.substring(0, encryptedBackup.ciphertext.length - 4) + 'ZZZZ',
    };
    await decryptBackupContainer(tamperedBackup, passphrase);
    throw new Error('SECURITY FAILURE: Tampered backup container was accepted!');
  } catch (err) {
    if (err.message.includes('SECURITY FAILURE')) throw err;
    console.log('✔ Security Validation Passed: Tampered backup container failed before import.');
  }

  // 11. Wrong Passphrase on Backup Container Test
  try {
    await decryptBackupContainer(encryptedBackup, 'wrong-password-with-sixteen-chars');
    throw new Error('SECURITY FAILURE: Backup decrypted with wrong passphrase!');
  } catch (err) {
    if (err.message.includes('SECURITY FAILURE')) throw err;
    console.log('✔ Security Validation Passed: Incorrect backup passphrase failed before import.');
  }

  console.log('\n🌟 ALL 11 CRYPTOGRAPHIC INTEGRITY & SECURITY TESTS PASSED! 🌟\n');
}

runTests().catch((e) => {
  console.error('Test Failed:', e);
  process.exit(1);
});
