package com.btekosistem.android.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class MapStore : KeyValueStore {
    val m = HashMap<String, String>()
    override fun get(key: String) = m[key]
    override fun put(key: String, value: String) { m[key] = value }
}

class LeAddressBookTest {
    @Test fun `kaydeder ve buyuk kucuk harf fark etmez`() {
        val store = MapStore()
        val b = LeAddressBook(store)
        assertNull(b.leFor("84:AC:60:20:9D:3A"))
        assertTrue(b.remember("84:ac:60:20:9d:3a", "c4:ac:60:20:9d:3b"))
        assertEquals("C4:AC:60:20:9D:3B", b.leFor("84:AC:60:20:9D:3A"))
        // yeni ornek ayni depodan okur (kalicilik)
        assertEquals("C4:AC:60:20:9D:3B", LeAddressBook(store).leFor("84:AC:60:20:9D:3A"))
    }

    @Test fun `ayni deger degisiklik sayilmaz gecersiz adres yok sayilir`() {
        val b = LeAddressBook(MapStore())
        assertTrue(b.remember("84:AC:60:20:9D:3A", "C4:AC:60:20:9D:3B"))
        assertFalse(b.remember("84:AC:60:20:9D:3A", "C4:AC:60:20:9D:3B"))
        assertFalse(b.remember("xyz", "C4:AC:60:20:9D:3B"))
        assertNull(b.leFor("xyz"))
    }
}
