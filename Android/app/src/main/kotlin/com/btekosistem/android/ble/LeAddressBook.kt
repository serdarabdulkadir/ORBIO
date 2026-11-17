package com.btekosistem.android.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.Context
import android.os.Build

/** Basit anahtar-deger deposu (SharedPreferences ya da test icin harita). */
interface KeyValueStore {
    fun get(key: String): String?
    fun put(key: String, value: String)
}

class PrefsKeyValueStore(context: Context) : KeyValueStore {
    private val prefs = context.applicationContext.getSharedPreferences("le_addr", Context.MODE_PRIVATE)
    override fun get(key: String): String? = prefs.getString(key, null)
    override fun put(key: String, value: String) { prefs.edit().putString(key, value).apply() }
}

/**
 * Klasik adres -> LE (kontrol) adresi kaydi. QCY'nin LE adresi sabittir; bir kez gorulunce kalici tutulur ve sonraki
 * baglantilarda taramadan dogrudan GATT'e gidilir. Android'e bagimli degil.
 */
class LeAddressBook(private val store: KeyValueStore) {
    /** Kaydeder; deger degistiyse true. Gecersiz adres yok sayilir. */
    fun remember(classic: String, le: String): Boolean {
        val c = normalize(classic) ?: return false
        val l = normalize(le) ?: return false
        if (store.get(KEY + c) == l) return false
        store.put(KEY + c, l)
        return true
    }

    fun leFor(classic: String): String? {
        val c = normalize(classic) ?: return null
        return store.get(KEY + c)?.let(::normalize)
    }

    companion object {
        private const val KEY = "le_"
        private val MAC = Regex("^([0-9A-F]{2}:){5}[0-9A-F]{2}$")

        fun normalize(addr: String): String? = addr.trim().uppercase().takeIf { MAC.matches(it) }
    }
}

object LeDevices {
    /** LE adresinden uzak cihaz: API 34+ getRemoteLeDevice(PUBLIC), daha eskide getRemoteDevice. */
    @SuppressLint("MissingPermission")
    fun remote(adapter: BluetoothAdapter?, addr: String): BluetoothDevice? {
        adapter ?: return null
        return try {
            if (Build.VERSION.SDK_INT >= 34) adapter.getRemoteLeDevice(addr, BluetoothDevice.ADDRESS_TYPE_PUBLIC)
            else adapter.getRemoteDevice(addr)
        } catch (_: IllegalArgumentException) {
            null
        }
    }
}
