package com.ourspace.our_space_mobile

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class QuickUnlockChannel(
    private val activity: FragmentActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    private val allowsDeviceCredential = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

    private val authenticators =
        if (allowsDeviceCredential) BIOMETRIC_STRONG or DEVICE_CREDENTIAL else BIOMETRIC_STRONG

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availability" -> result.success(availability())
            "seal" -> seal(call, result)
            "open" -> open(call, result)
            "forget" -> {
                runCatching { deleteKey() }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun availability(): String =
        when (BiometricManager.from(activity).canAuthenticate(authenticators)) {
            BiometricManager.BIOMETRIC_SUCCESS -> "ready"
            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED -> "none-enrolled"
            else -> "unsupported"
        }

    private fun seal(call: MethodCall, result: MethodChannel.Result) {
        val secret = call.argument<ByteArray>("secret")
        val aad = call.argument<ByteArray>("aad")
        if (secret == null || aad == null) {
            result.error("failed", "Missing arguments.", null)
            return
        }
        val cipher = try {
            deleteKey()
            Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, createKey()) }
        } catch (e: Exception) {
            result.error("failed", e.javaClass.simpleName, null)
            return
        }
        authenticate(call, cipher, result) { unlocked ->
            unlocked.updateAAD(aad)
            val ciphertext = unlocked.doFinal(secret)
            mapOf("iv" to unlocked.iv, "ciphertext" to ciphertext)
        }
    }

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        val iv = call.argument<ByteArray>("iv")
        val ciphertext = call.argument<ByteArray>("ciphertext")
        val aad = call.argument<ByteArray>("aad")
        if (iv == null || ciphertext == null || aad == null) {
            result.error("failed", "Missing arguments.", null)
            return
        }
        val key = runCatching { loadKey() }.getOrNull()
        if (key == null) {
            result.error("stale", "There is no key on this phone.", null)
            return
        }
        val cipher = try {
            Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            runCatching { deleteKey() }
            result.error("stale", "The fingerprints or face on this phone changed.", null)
            return
        } catch (e: Exception) {
            result.error("failed", e.javaClass.simpleName, null)
            return
        }
        authenticate(call, cipher, result) { unlocked ->
            unlocked.updateAAD(aad)
            unlocked.doFinal(ciphertext)
        }
    }

    private fun authenticate(
        call: MethodCall,
        cipher: Cipher,
        result: MethodChannel.Result,
        finish: (Cipher) -> Any,
    ) {
        var replied = false
        fun reply(block: () -> Unit) {
            if (replied) return
            replied = true
            block()
        }

        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(call.argument<String>("title") ?: "Our Space")
            .setAllowedAuthenticators(authenticators)
            .apply {
                call.argument<String>("subtitle")?.let { setSubtitle(it) }
                if (!allowsDeviceCredential) setNegativeButtonText(call.argument<String>("cancel") ?: "Cancel")
            }
            .build()

        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(outcome: BiometricPrompt.AuthenticationResult) {
                val unlocked = outcome.cryptoObject?.cipher
                if (unlocked == null) {
                    reply { result.error("failed", "No cipher came back.", null) }
                    return
                }
                try {
                    val value = finish(unlocked)
                    reply { result.success(value) }
                } catch (e: AEADBadTagException) {
                    reply { result.error("stale", "The saved key could not be opened.", null) }
                } catch (e: Exception) {
                    reply { result.error("failed", e.javaClass.simpleName, null) }
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                reply { result.error(codeFor(errorCode), errString.toString(), null) }
            }
        }

        try {
            BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
                .authenticate(info, BiometricPrompt.CryptoObject(cipher))
        } catch (e: Exception) {
            reply { result.error("failed", e.javaClass.simpleName, null) }
        }
    }

    private fun codeFor(errorCode: Int): String = when (errorCode) {
        BiometricPrompt.ERROR_USER_CANCELED,
        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
        BiometricPrompt.ERROR_CANCELED,
        BiometricPrompt.ERROR_TIMEOUT -> "cancelled"
        BiometricPrompt.ERROR_LOCKOUT,
        BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockout"
        BiometricPrompt.ERROR_NO_BIOMETRICS,
        BiometricPrompt.ERROR_HW_NOT_PRESENT,
        BiometricPrompt.ERROR_HW_UNAVAILABLE,
        BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL -> "unsupported"
        else -> "failed"
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun loadKey(): SecretKey? = keyStore().getKey(ALIAS, null) as SecretKey?

    private fun deleteKey() {
        val store = keyStore()
        if (store.containsAlias(ALIAS)) store.deleteEntry(ALIAS)
    }

    private fun createKey(): SecretKey {
        val spec = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(KEY_BITS)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .apply {
                if (allowsDeviceCredential) {
                    setUserAuthenticationParameters(
                        0,
                        KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL,
                    )
                }
            }
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).run {
            init(spec)
            generateKey()
        }
    }

    private companion object {
        const val CHANNEL = "our_space/quick_unlock"
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "our_space_quick_unlock"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val KEY_BITS = 256
        const val TAG_BITS = 128
    }
}
