package com.btekosistem.android.peer

/** Aranabilir numara metni: bosluk, tire, parantez atilir; yalniz 0-9 + * # kalir. Gecersizse null. */
fun normalizeDialNumber(raw: String): String? {
    val s = raw.filterNot { it == ' ' || it == '-' || it == '(' || it == ')' || it == '.' }
    if (s.isEmpty() || s.length > 32) return null
    return if (s.all { it.isDigit() || it == '+' || it == '*' || it == '#' }) s else null
}
