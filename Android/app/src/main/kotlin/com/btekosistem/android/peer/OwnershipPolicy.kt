package com.btekosistem.android.peer

/**
 * Kulakligin tek LE baglantisi kimde: ilk yonetmeye baslayan cihazda kalir; diger cihaz zorla almaz ve otomatik GATT
 * denemez, karti relay ile gosterir. El degistirme yalniz kullanici dugmesiyle ya da sahibin kalici kopmasiyla olur.
 * Saf mantik (Mac tarafi ayni kurali uygular).
 */
object OwnershipPolicy {
    /**
     * Telefon otomatik GATT acabilir mi? Peer oturumu yoksa evet; oturum aciksa yalniz Mac sahip degilse VE kullanici
     * telefondan yonetmeye basladiysa (Mac onceliklidir).
     */
    fun autoGattAllowed(sessionOpen: Boolean, macOwns: Boolean, phoneEngaged: Boolean): Boolean =
        if (!sessionOpen) true else !macOwns && phoneEngaged

    /** Mac sahipligi biraktiktan sonra telefon GATT'e doner mi (sahibin kalici kopmasi): otomatik acik ve "Mac'e ver" yoksa. */
    fun returnToGattAfterMacRelease(autoEnabled: Boolean, forcedPhone: Boolean): Boolean = autoEnabled && !forcedPhone
}
