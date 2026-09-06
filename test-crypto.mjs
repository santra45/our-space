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
} from './src/services/crypto.js';

async function runTests() {
  console.log('--- Starting Web Crypto Verification Suite ---');

  const passphrase = 'my-super-secret-couple-passphrase-2026';
  const salt = generateSalt();
  console.log('✔ Generated Vault Salt:', salt);

  // 1. Derive Key
  const key1 = await deriveKeyFromPassphrase(passphrase, salt);
  const key2 = await deriveKeyFromPassphrase(passphrase, salt);
  console.log('✔ PBKDF2 Key Derived Successfully');

  // 2. Encrypt and Decrypt Text
  const message = 'I love you to the moon and back 💕';
  const { ciphertext, iv } = await encryptText(message, key1);
  console.log('✔ Encrypted Text (IV length = 12 bytes, Ciphertext generated)');

  const decrypted = await decryptText(ciphertext, iv, key2);
  if (decrypted !== message) {
    throw new Error(`Decrypted text mismatch! Expected "${message}", got "${decrypted}"`);
  }
  console.log('✔ Decrypted Text matches perfectly:', decrypted);

  // 3. Encrypt and Decrypt JSON
  const memoryObj = {
    caption: 'Our first sunset in Bali 🌅',
    date: '2026-06-15',
    tags: ['beach', 'sunset', 'love'],
  };
  const jsonEncrypted = await encryptJSON(memoryObj, key1);
  const jsonDecrypted = await decryptJSON(jsonEncrypted.ciphertext, jsonEncrypted.iv, key2);
  if (JSON.stringify(jsonObjToString(memoryObj)) !== JSON.stringify(jsonObjToString(jsonDecrypted))) {
    throw new Error('JSON roundtrip mismatch!');
  }
  console.log('✔ JSON Object Encrypted and Decrypted successfully:', jsonDecrypted);

  // 4. Encrypt and Decrypt Binary Blob
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

  // 5. Tamper / Authentication Tag Verification Test
  try {
    const tamperedCipher = ciphertext.substring(0, ciphertext.length - 4) + 'AAAA';
    await decryptText(tamperedCipher, iv, key1);
    throw new Error('SECURITY FAILURE: Tampered ciphertext was accepted!');
  } catch (err) {
    if (err.message.includes('SECURITY FAILURE')) throw err;
    console.log('✔ Security Validation Passed: Tampered ciphertext was rejected by AES-GCM auth tag.');
  }

  // 6. Wrong Passphrase Test
  const wrongKey = await deriveKeyFromPassphrase('wrong-passphrase', salt);
  try {
    await decryptText(ciphertext, iv, wrongKey);
    throw new Error('SECURITY FAILURE: Decryption succeeded with wrong passphrase!');
  } catch (err) {
    if (err.message.includes('SECURITY FAILURE')) throw err;
    console.log('✔ Security Validation Passed: Incorrect passphrase was rejected.');
  }

  console.log('\n🌟 ALL 6 CRYPTOGRAPHIC INTEGRITY TESTS PASSED! 🌟\n');
}

function jsonObjToString(obj) {
  return JSON.parse(JSON.stringify(obj));
}

runTests().catch((e) => {
  console.error('Test Failed:', e);
  process.exit(1);
});
