package dev.zowy.zowy_adblocker

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private fun configurationKey(): SecretKey {
    val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    val existing = store.getKey("zowy.configuration.v1", null)
    if (existing != null) return existing as SecretKey
    return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
        init(KeyGenParameterSpec.Builder("zowy.configuration.v1",
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
    }.generateKey()
}

@Synchronized
fun Context.readConfiguration(backup: Boolean = false): String? {
    val value = preferences().getString(if (backup) "backupCipher" else "configCipher", null) ?: return null
    val data = Base64.decode(value, Base64.NO_WRAP)
    require(data.size >= 28) { "Encrypted configuration is damaged" }
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.DECRYPT_MODE, configurationKey(), GCMParameterSpec(128, data.copyOfRange(0, 12)))
    return cipher.doFinal(data.copyOfRange(12, data.size)).toString(Charsets.UTF_8)
}

@Synchronized
fun Context.writeConfiguration(text: String) {
    // Filter refreshes must not overwrite the previous distinct settings backup.
    if (readConfiguration() == text) return
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, configurationKey())
    val encrypted = Base64.encodeToString(cipher.iv + cipher.doFinal(text.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
    val prefs = preferences()
    val old = prefs.getString("configCipher", null)
    val edit = prefs.edit()
    if (old != null) edit.putString("backupCipher", old)
    check(edit.putString("configCipher", encrypted).commit()) { "Could not persist encrypted settings" }
}
