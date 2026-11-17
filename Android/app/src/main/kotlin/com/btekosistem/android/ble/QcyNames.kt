package com.btekosistem.android.ble

/** Eslesmis cihaz adindan QCY kulaklik tespiti (reklam gelmese de listelemek icin). */
object QcyNames {
    private val markers = listOf("qcy", "melobuds", "melo buds", "melo")

    fun isQcy(name: String?): Boolean {
        val n = name?.trim()?.lowercase() ?: return false
        return n.isNotEmpty() && markers.any { n.contains(it) }
    }
}
