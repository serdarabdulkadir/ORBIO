package com.btekosistem.android.peer

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.security.KeyStore
import java.security.PrivateKey
import java.util.Base64
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Telefon tarafi izin anahtarlari (Mac'e verilen yetkiler) ve otomatik gecis. Izinler varsayilan KAPALI. */
data class PeerSettings(
    val callControl: Boolean = false,
    val contacts: Boolean = false,
    val callLog: Boolean = false,
    val autoSwitch: Boolean = true,
)

class PinnedMac(val id: String, val name: String, val pub: ByteArray)

class PeerIdentity(val privateKey: PrivateKey, val publicBytes: ByteArray)

/** Kimlik anahtari Android Keystore'daki AES anahtariyla sarilip SharedPreferences'ta saklanir. */
class PeerStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("peer", Context.MODE_PRIVATE)
    private val b64e = Base64.getEncoder()
    private val b64d = Base64.getDecoder()

    private val _settings = MutableStateFlow(readSettings())
    val settings: StateFlow<PeerSettings> = _settings.asStateFlow()

    private val _pinned = MutableStateFlow(readPinned())
    val pinned: StateFlow<PinnedMac?> = _pinned.asStateFlow()

    var enabled: Boolean
        get() = prefs.getBoolean("enabled", false)
        set(v) { prefs.edit().putBoolean("enabled", v).apply() }

    /** Son basarili Mac baglantisi (epoch ms); 0 = hic. */
    var lastConnected: Long
        get() = prefs.getLong("last_connected", 0L)
        set(v) { prefs.edit().putLong("last_connected", v).apply() }

    val deviceId: String
        @Synchronized get() = prefs.getString("device_id", null)
            ?: UUID.randomUUID().toString().also { prefs.edit().putString("device_id", it).apply() }

    private fun readSettings() = PeerSettings(
        callControl = prefs.getBoolean("perm_call", false),
        contacts = prefs.getBoolean("perm_contacts", false),
        callLog = prefs.getBoolean("perm_calllog", false),
        autoSwitch = prefs.getBoolean("auto_switch", true),
    )

    @Synchronized
    fun update(transform: (PeerSettings) -> PeerSettings) {
        val s = transform(_settings.value)
        prefs.edit()
            .putBoolean("perm_call", s.callControl).putBoolean("perm_contacts", s.contacts)
            .putBoolean("perm_calllog", s.callLog).putBoolean("auto_switch", s.autoSwitch)
            .apply()
        _settings.value = s
    }

    private fun readPinned(): PinnedMac? {
        val id = prefs.getString("pin_id", null) ?: return null
        val pub = prefs.getString("pin_pub", null) ?: return null
        return PinnedMac(id, prefs.getString("pin_name", "") ?: "", b64d.decode(pub))
    }

    fun pin(mac: PinnedMac) {
        prefs.edit().putString("pin_id", mac.id).putString("pin_name", mac.name).putString("pin_pub", b64e.encodeToString(mac.pub)).apply()
        _pinned.value = mac
    }

    fun unpin() {
        prefs.edit().remove("pin_id").remove("pin_name").remove("pin_pub").apply()
        _pinned.value = null
    }

    @Synchronized
    fun identity(): PeerIdentity {
        val blob = prefs.getString("id_blob", null)
        if (blob != null) {
            val plain = decrypt(b64d.decode(blob))
            return PeerIdentity(P256.privateKeyFromRaw(plain.copyOfRange(0, 32)), plain.copyOfRange(32, 97))
        }
        val (priv, pub) = P256.generate()
        prefs.edit().putString("id_blob", b64e.encodeToString(encrypt(priv + pub))).apply()
        return PeerIdentity(P256.privateKeyFromRaw(priv), pub)
    }

    private fun wrapKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    private fun encrypt(plain: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, wrapKey())
        return c.iv + c.doFinal(plain)
    }

    private fun decrypt(blob: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, wrapKey(), GCMParameterSpec(128, blob, 0, 12))
        return c.doFinal(blob, 12, blob.size - 12)
    }

    private companion object {
        const val ALIAS = "bt_peer_wrap"
    }
}
