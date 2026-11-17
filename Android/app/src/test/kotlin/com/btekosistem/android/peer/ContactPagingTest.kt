package com.btekosistem.android.peer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ContactPagingTest {
    @Test fun `sayfa boyutu sinirlanir`() {
        assertEquals(40, ContactPaging.clampContacts(null))
        assertEquals(1, ContactPaging.clampContacts(0))
        assertEquals(100, ContactPaging.clampContacts(5000))
        assertEquals(100, ContactPaging.clampLog(null))
        assertEquals(200, ContactPaging.clampLog(1_000_000))
    }

    @Test fun `son sayfa tespiti`() {
        assertTrue(ContactPaging.isLast(0, 0, 0))
        assertTrue(ContactPaging.isLast(80, 20, 100))
        assertFalse(ContactPaging.isLast(0, 40, 100))
        assertTrue(ContactPaging.isLast(100, 0, 100))
    }

    @Test fun `sayfa butcesi en az bir kayit tasir`() {
        val items = listOf(300, 300, 300)
        assertEquals(listOf(300, 300), ContactPaging.takeWithinBudget(items, { it }, 650))
        assertEquals(listOf(300), ContactPaging.takeWithinBudget(items, { it }, 100))
        assertEquals(items, ContactPaging.takeWithinBudget(items, { it }, 10_000))
    }
}
