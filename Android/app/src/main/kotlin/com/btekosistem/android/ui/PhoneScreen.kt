package com.btekosistem.android.ui

import android.Manifest
import android.os.Build
import android.os.SystemClock
import android.text.format.DateUtils
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Call
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.btekosistem.android.R
import com.btekosistem.android.ble.BtEnvironment
import com.btekosistem.android.peer.ActionResult
import com.btekosistem.android.peer.CallInfo
import com.btekosistem.android.peer.MacPhase
import com.btekosistem.android.peer.MacReason
import com.btekosistem.android.peer.MacService
import com.btekosistem.android.peer.MacUi
import com.btekosistem.android.peer.PeerCallLogEntry
import com.btekosistem.android.peer.PeerContact
import com.btekosistem.android.peer.PeerManager
import com.btekosistem.android.peer.PhoneInfo
import com.btekosistem.android.peer.normalizeDialNumber
import com.btekosistem.android.ui.theme.BtShape
import com.btekosistem.android.ui.theme.BtType
import com.btekosistem.android.ui.theme.Space
import com.btekosistem.android.ui.theme.bt
import kotlinx.coroutines.delay

class PhonePerms(val state: PermAccess, val answer: PermAccess, val call: PermAccess, val contacts: PermAccess, val callLog: PermAccess)

data class PhoneUiModel(
    val call: CallInfo = CallInfo(),
    /** SystemClock.elapsedRealtime (sure sayaci icin). */
    val now: Long = 0L,
    val info: PhoneInfo,
    val mac: MacUi = MacUi(),
    val number: String = "",
    val suggestions: List<PeerContact> = emptyList(),
    val recents: List<PeerCallLogEntry> = emptyList(),
    val missedOnly: Boolean = false,
    val perms: PhonePerms,
    val note: Int? = null,
    val bluetoothNote: Boolean = false,
)

class PhoneActions(
    val onNumber: (String) -> Unit = {},
    val onDial: () -> Unit = {},
    val onAnswer: () -> Unit = {},
    val onReject: () -> Unit = {},
    val onHangup: () -> Unit = {},
    val onMissedOnly: (Boolean) -> Unit = {},
    val onMacEnable: () -> Unit = {},
    val onMacDisable: () -> Unit = {},
    val onMacPair: (MacService, String?) -> Unit = { _, _ -> },
    val onMacUnpair: () -> Unit = {},
    val onSas: (Boolean) -> Unit = {},
    val onMacReconnect: () -> Unit = {},
    val onBatteryFix: () -> Unit = {},
)

/** Durum tutan sarmalayici: izinler, arama durumu, Mac yoneticisi. */
@Composable
fun PhoneScreen(contentPadding: PaddingValues) {
    val ctx = LocalContext.current
    val mgr = remember { PeerManager.get(ctx) }
    val phone = mgr.phone
    val mac by mgr.state.collectAsStateWithLifecycle()
    val call by phone.call.collectAsStateWithLifecycle()
    val info by phone.info.collectAsStateWithLifecycle()
    var number by rememberSaveable { mutableStateOf("") }
    var missedOnly by rememberSaveable { mutableStateOf(false) }
    var note by remember { mutableStateOf<Int?>(null) }
    val perms = PhonePerms(
        rememberPerm(Manifest.permission.READ_PHONE_STATE), rememberPerm(Manifest.permission.ANSWER_PHONE_CALLS),
        rememberPerm(Manifest.permission.CALL_PHONE), rememberPerm(Manifest.permission.READ_CONTACTS),
        rememberPerm(Manifest.permission.READ_CALL_LOG),
    )
    val now by produceState(SystemClock.elapsedRealtime()) {
        while (true) { delay(1000); value = SystemClock.elapsedRealtime() }
    }
    val suggestions by produceState(emptyList<PeerContact>(), number, perms.contacts.granted) {
        value = if (perms.contacts.granted && number.trim().length >= 2) {
            delay(200)
            phone.searchContacts(number)
        } else emptyList()
    }
    val allRecents by produceState(emptyList<PeerCallLogEntry>(), call.durum, perms.callLog.granted) {
        value = if (perms.callLog.granted) phone.recentCalls(40) else emptyList()
    }
    val notifLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { mgr.enable() }

    fun report(r: ActionResult) {
        note = when (r) {
            ActionResult.UNSUPPORTED -> R.string.call_unsupported
            ActionResult.FAILED, ActionResult.INVALID -> R.string.call_failed
            else -> null
        }
    }

    val actions = PhoneActions(
        onNumber = { number = it },
        onDial = {
            if (!perms.call.granted) perms.call.act()
            else if (normalizeDialNumber(number) != null) { report(phone.dial(number)); number = "" }
        },
        onAnswer = { report(phone.answer()) },
        onReject = { report(phone.endCall()) },
        onHangup = { report(phone.endCall()) },
        onMissedOnly = { missedOnly = it },
        onMacEnable = {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !BtEnvironment.isGranted(ctx, Manifest.permission.POST_NOTIFICATIONS)) {
                notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else mgr.enable()
        },
        onMacDisable = mgr::disable,
        onMacPair = mgr::pair,
        onMacUnpair = mgr::unpair,
        onSas = mgr::confirmSas,
        onMacReconnect = mgr::reconnectNow,
        onBatteryFix = { BackgroundAccess.requestBattery(ctx) },
    )
    PhoneContent(
        PhoneUiModel(
            call = call, now = now, info = info, mac = mac, number = number, suggestions = suggestions,
            recents = if (missedOnly) allRecents.filter { it.yon == "cevapsiz" } else allRecents,
            missedOnly = missedOnly, perms = perms, note = note,
        ),
        actions, contentPadding,
    )
}

@Composable
fun PhoneContent(m: PhoneUiModel, a: PhoneActions, contentPadding: PaddingValues) {
    val c = MaterialTheme.bt
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            start = Space.lg, end = Space.lg,
            top = contentPadding.calculateTopPadding() + Space.lg,
            bottom = contentPadding.calculateBottomPadding() + Space.lg,
        ),
        verticalArrangement = Arrangement.spacedBy(Space.md),
    ) {
        item { Text(stringResource(R.string.nav_phone), style = BtType.pageTitle, color = c.text) }
        if (m.call.durum != "bosta") item { CallCard(m, a) }
        item { MacCard(m.mac, a) }
        item { StatusCard(m) }
        item { DialerCard(m, a) }
        item { RecentsCard(m, a) }
    }
    if (m.mac.phase == MacPhase.SAS && m.mac.sas != null) SasDialog(m.mac.sas, a.onSas)
}

private fun onStatus(dark: Boolean) = if (dark) Color(0xFF06111F) else Color.White

@Composable
private fun Avatar(label: String, size: Int) {
    val c = MaterialTheme.bt
    Box(Modifier.size(size.dp).clip(CircleShape).background(c.navySoft), contentAlignment = Alignment.Center) {
        Text(
            label.trim().firstOrNull { it.isLetterOrDigit() }?.uppercase() ?: "#",
            style = BtType.cardTitle.copy(fontSize = (size / 2.4f).sp, lineHeight = (size / 2f).sp), color = c.accentText,
        )
    }
}

private fun elapsed(sec: Long): String = "%02d:%02d".format(sec / 60, sec % 60)

@Composable
private fun CallCard(m: PhoneUiModel, a: PhoneActions) {
    val c = MaterialTheme.bt
    val call = m.call
    val ringing = call.durum == "caliyor"
    val title = call.kisiAdi ?: call.numara ?: stringResource(R.string.call_unknown)
    val status = when (call.durum) {
        "caliyor" -> R.string.call_incoming
        "acik" -> R.string.call_active
        else -> R.string.call_dialing
    }
    BtCard {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.md)) {
            Chip(stringResource(status), c.accentText, c.navySoft)
            Avatar(title, 88)
            Text(title, style = BtType.cardTitle, color = c.text, textAlign = TextAlign.Center, maxLines = 2)
            if (call.kisiAdi != null && call.numara != null) Text(call.numara, style = BtType.body, color = c.textSecondary)
            call.startedAt?.let {
                Text(elapsed(((m.now - it) / 1000).coerceAtLeast(0)), style = BtType.numLarge, color = c.text)
            }
        }
        if (!m.perms.answer.granted) {
            EmptyState(
                Icons.Rounded.Lock, stringResource(R.string.call_perm_title), stringResource(R.string.call_perm_body),
                action = stringResource(if (m.perms.answer.blocked) R.string.perm_open_settings else R.string.perm_allow),
                onAction = m.perms.answer.act,
            )
        } else {
            val ink = onStatus(c.dark)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                if (ringing) {
                    RoundButton(BtIcons.CallEnd, stringResource(R.string.call_reject), c.down, ink, a.onReject)
                    RoundButton(Icons.Rounded.Call, stringResource(R.string.call_answer), c.up, ink, a.onAnswer)
                } else {
                    RoundButton(BtIcons.CallEnd, stringResource(R.string.call_hangup), c.down, ink, a.onHangup)
                }
            }
        }
        m.note?.let { Text(stringResource(it), style = BtType.caption, color = c.down) }
    }
}

@Composable
private fun MacCard(mac: MacUi, a: PhoneActions) {
    val c = MaterialTheme.bt
    var pairTarget by remember { mutableStateOf<MacService?>(null) }
    var lastPicked by remember { mutableStateOf<MacService?>(null) }
    // Once kodsuz denenir; Mac aktif kod uretmisse (kod_gerekli) kod diyalogu acilir.
    androidx.compose.runtime.LaunchedEffect(mac.reason) {
        if (mac.reason == MacReason.PAIR_NEED_CODE && lastPicked != null) pairTarget = lastPicked
    }
    pairTarget?.let { t ->
        PairCodeDialog(t.name, onDismiss = { pairTarget = null }, onConnect = { code -> lastPicked = t; a.onMacPair(t, code); pairTarget = null })
    }
    BtCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                SectionLabel(stringResource(R.string.mac_title))
                val head = when (mac.phase) {
                    MacPhase.OFF -> R.string.mac_off
                    MacPhase.SEARCHING -> R.string.mac_searching
                    MacPhase.CONNECTING -> R.string.mac_connecting
                    MacPhase.SAS -> R.string.svc_sas
                    MacPhase.CONNECTED -> R.string.mac_connected
                    MacPhase.BACKOFF -> R.string.mac_reconnecting
                    MacPhase.KEY_CHANGED -> R.string.mac_key_changed_title
                }
                Text(stringResource(head), style = BtType.cardTitle, color = if (mac.phase == MacPhase.KEY_CHANGED) c.down else c.text, maxLines = 2)
                if (mac.phase == MacPhase.CONNECTED && mac.macName != null) Text(mac.macName, style = BtType.body, color = c.textSecondary)
                if (mac.phase == MacPhase.CONNECTED && mac.path != null) {
                    val pathName = stringResource(if (mac.path == com.btekosistem.android.peer.PeerPath.BLUETOOTH) R.string.mac_path_bt else R.string.mac_path_wifi)
                    Text(stringResource(R.string.mac_path, pathName), style = BtType.caption, color = c.textSecondary)
                    if (mac.path == com.btekosistem.android.peer.PeerPath.BLUETOOTH) Text(stringResource(R.string.mac_bt_only), style = BtType.caption, color = c.textSecondary)
                }
            }
            when (mac.phase) {
                MacPhase.CONNECTED -> StatusDot(c.up, 12.dp)
                MacPhase.CONNECTING, MacPhase.BACKOFF, MacPhase.SEARCHING ->
                    CircularProgressIndicator(Modifier.size(22.dp), color = c.navy, strokeWidth = 2.dp)
                else -> {}
            }
        }
        when (mac.phase) {
            MacPhase.OFF -> {
                Text(stringResource(R.string.mac_off_body), style = BtType.body, color = c.textSecondary)
                BtButton(stringResource(R.string.mac_connect), a.onMacEnable, Modifier.fillMaxWidth())
                Text(stringResource(R.string.mac_notif_note), style = BtType.caption, color = c.textSecondary)
            }
            MacPhase.KEY_CHANGED -> {
                Text(stringResource(R.string.mac_key_changed_body), style = BtType.body, color = c.textSecondary)
                BtButton(stringResource(R.string.mac_unpair), a.onMacUnpair, Modifier.fillMaxWidth(), container = c.down)
            }
            else -> {
                if (mac.pairedName == null && mac.phase == MacPhase.SEARCHING) {
                    if (mac.found.isEmpty()) {
                        Text(stringResource(R.string.mac_none_found), style = BtType.body, color = c.textSecondary)
                    } else {
                        SectionLabel(stringResource(R.string.mac_pick))
                        mac.found.forEach { f ->
                            Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                                Column(Modifier.weight(1f)) {
                                    Text(f.name, style = BtType.rowTitle, color = c.text, maxLines = 2)
                                    if (com.btekosistem.android.peer.PeerPathPolicy.isProvisionalId(f.id)) Text(stringResource(R.string.mac_via_bt), style = BtType.caption, color = c.textSecondary)
                                }
                                BtButton(stringResource(R.string.mac_pair), { lastPicked = f; a.onMacPair(f, null) }, primary = false)
                            }
                        }
                    }
                } else if (mac.pairedName != null) {
                    Text(stringResource(R.string.mac_paired_with, mac.pairedName), style = BtType.caption, color = c.textSecondary)
                }
                if (mac.pairedName == null && mac.phase != MacPhase.CONNECTED && mac.phase != MacPhase.SAS) {
                    mac.reason?.let { r -> Text(stringResource(reasonText(r)), style = BtType.body, color = c.down) }
                }
                if (mac.pairedName != null && mac.phase != MacPhase.CONNECTED && mac.phase != MacPhase.SAS) {
                    mac.reason?.let { r ->
                        Text(
                            stringResource(when (r) {
                                MacReason.NOT_FOUND -> R.string.mac_reason_notfound
                                MacReason.REFUSED -> R.string.mac_reason_refused
                                MacReason.TIMEOUT -> R.string.mac_reason_timeout
                                MacReason.LOST -> R.string.mac_reason_lost
                                MacReason.HANDSHAKE -> R.string.mac_reason_handshake
                                MacReason.PAIR_NEED_CODE -> R.string.pair_err_need_code
                                MacReason.PAIR_WRONG -> R.string.pair_err_wrong
                                MacReason.PAIR_LOCKED -> R.string.pair_err_locked
                            }),
                            style = BtType.body, color = c.down,
                        )
                    }
                    if (mac.lastConnectedAt > 0L) {
                        val t = java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.SHORT, java.text.DateFormat.SHORT).format(java.util.Date(mac.lastConnectedAt))
                        Text(stringResource(R.string.mac_last_ok, t), style = BtType.caption, color = c.textSecondary)
                    }
                    BtButton(stringResource(R.string.mac_reconnect), a.onMacReconnect, Modifier.fillMaxWidth())
                    Text(
                        stringResource(R.string.mac_battery_hint), style = BtType.caption, color = c.textSecondary,
                        modifier = Modifier.fillMaxWidth().clickable(onClick = a.onBatteryFix).padding(vertical = Space.sm),
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                    BtButton(stringResource(R.string.mac_disconnect), a.onMacDisable, Modifier.weight(1f), primary = false)
                    if (mac.pairedName != null) BtButton(stringResource(R.string.mac_unpair), a.onMacUnpair, Modifier.weight(1f), primary = false)
                }
            }
        }
    }
}

private fun reasonText(r: MacReason): Int = when (r) {
    MacReason.NOT_FOUND -> R.string.mac_reason_notfound
    MacReason.REFUSED -> R.string.mac_reason_refused
    MacReason.TIMEOUT -> R.string.mac_reason_timeout
    MacReason.LOST -> R.string.mac_reason_lost
    MacReason.HANDSHAKE -> R.string.mac_reason_handshake
    MacReason.PAIR_NEED_CODE -> R.string.pair_err_need_code
    MacReason.PAIR_WRONG -> R.string.pair_err_wrong
    MacReason.PAIR_LOCKED -> R.string.pair_err_locked
}

/** Mac'te "Telefonu esle" ile uretilen 6 haneli kodun girildigi diyalog. */
@Composable
private fun PairCodeDialog(macName: String, onDismiss: () -> Unit, onConnect: (String) -> Unit) {
    val c = MaterialTheme.bt
    var code by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = c.card,
        title = { Text(stringResource(R.string.pair_code_title, macName), style = BtType.cardTitle, color = c.text) },
        text = {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.md)) {
                Text(stringResource(R.string.pair_code_body), style = BtType.body, color = c.textSecondary, textAlign = TextAlign.Center)
                BasicTextField(
                    value = code,
                    onValueChange = { v -> code = v.filter { it.isDigit() }.take(6) },
                    singleLine = true,
                    textStyle = BtType.pageTitle.copy(fontSize = 36.sp, lineHeight = 44.sp, fontFamily = FontFamily.Monospace, color = c.accentText, textAlign = TextAlign.Center),
                    cursorBrush = SolidColor(c.navy),
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.NumberPassword),
                    modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
                )
            }
        },
        confirmButton = {
            TextButton({ if (code.length == 6) onConnect(code) }, Modifier.heightIn(min = 48.dp), enabled = code.length == 6) {
                Text(stringResource(R.string.pair_code_go), style = BtType.rowTitle, color = c.accentText)
            }
        },
        dismissButton = { TextButton(onDismiss, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.pair_code_cancel), style = BtType.rowTitle, color = c.textSecondary) } },
    )
}

@Composable
private fun SasDialog(code: String, onSas: (Boolean) -> Unit) {
    val c = MaterialTheme.bt
    AlertDialog(
        onDismissRequest = {},
        containerColor = c.card,
        title = { Text(stringResource(R.string.sas_title), style = BtType.cardTitle, color = c.text) },
        text = {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.md)) {
                Text(
                    code.chunked(3).joinToString(" "),
                    style = BtType.pageTitle.copy(fontSize = 40.sp, lineHeight = 48.sp, fontFamily = FontFamily.Monospace),
                    color = c.accentText,
                )
                Text(stringResource(R.string.sas_body), style = BtType.body, color = c.textSecondary, textAlign = TextAlign.Center)
            }
        },
        confirmButton = { TextButton({ onSas(true) }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.sas_same), style = BtType.rowTitle, color = c.accentText) } },
        dismissButton = { TextButton({ onSas(false) }, Modifier.heightIn(min = 48.dp)) { Text(stringResource(R.string.sas_diff), style = BtType.rowTitle, color = c.down) } },
    )
}

@Composable
private fun SignalBars(level: Int) {
    val c = MaterialTheme.bt
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.Bottom, modifier = Modifier.height(22.dp)) {
        for (i in 1..4) {
            Box(Modifier.width(5.dp).height((6 + i * 4).dp).clip(RoundedCornerShape(2.dp)).background(if (i <= level) c.accent else c.separator))
        }
    }
}

@Composable
private fun StatTile(label: String, sub: String, subColor: Color, modifier: Modifier, value: @Composable () -> Unit) {
    val c = MaterialTheme.bt
    Column(
        modifier.clip(RoundedCornerShape(BtShape.md)).background(c.fill).padding(Space.md),
        verticalArrangement = Arrangement.spacedBy(Space.xs),
    ) {
        Text(label, style = BtType.caption, color = c.textSecondary)
        Box(Modifier.height(28.dp), contentAlignment = Alignment.CenterStart) { value() }
        Text(sub, style = BtType.caption, color = subColor, maxLines = 1)
    }
}

@Composable
private fun StatusCard(m: PhoneUiModel) {
    val c = MaterialTheme.bt
    BtCard {
        SectionLabel(m.info.ad)
        Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            StatTile(
                stringResource(R.string.st_battery),
                stringResource(if (m.info.sarj) R.string.st_charging else R.string.st_discharging),
                if (m.info.sarj) c.up else c.textSecondary, Modifier.weight(1f).fillMaxHeight(),
            ) {
                Text("%${m.info.pil}", style = BtType.numLarge, color = if (m.info.pil <= LOW_BATTERY && !m.info.sarj) c.down else c.text, maxLines = 1)
            }
            StatTile(
                stringResource(R.string.st_signal),
                stringResource(when (m.info.sinyal) { 0 -> R.string.sig_none; 1 -> R.string.sig_weak; 2 -> R.string.sig_fair; 3 -> R.string.sig_good; else -> R.string.sig_great }),
                if (m.info.sinyal <= 1) c.down else c.textSecondary, Modifier.weight(1f).fillMaxHeight(),
            ) { SignalBars(m.info.sinyal) }
            StatTile(
                stringResource(R.string.st_network),
                stringResource(when (m.info.ag) { "wifi" -> R.string.net_wifi_sub; "mobil" -> R.string.net_mobile_sub; else -> R.string.net_none_sub }),
                c.textSecondary, Modifier.weight(1f).fillMaxHeight(),
            ) {
                Text(
                    stringResource(when (m.info.ag) { "wifi" -> R.string.net_wifi; "mobil" -> R.string.net_mobile; else -> R.string.net_none }),
                    style = BtType.numLarge, color = c.text, maxLines = 1,
                )
            }
        }
        if (!m.perms.state.granted) {
            EmptyState(
                Icons.Rounded.Info, stringResource(R.string.perm_state_title), stringResource(R.string.perm_state_body),
                action = stringResource(if (m.perms.state.blocked) R.string.perm_open_settings else R.string.perm_allow),
                onAction = m.perms.state.act,
            )
        }
    }
}

private val KEYS = listOf(
    "1" to "", "2" to "ABC", "3" to "DEF", "4" to "GHI", "5" to "JKL", "6" to "MNO",
    "7" to "PQRS", "8" to "TUV", "9" to "WXYZ", "*" to "", "0" to "+", "#" to "",
)

@Composable
private fun DialerCard(m: PhoneUiModel, a: PhoneActions) {
    val c = MaterialTheme.bt
    val valid = normalizeDialNumber(m.number) != null
    BtCard {
        SectionLabel(stringResource(R.string.dial_title))
        Row(
            Modifier.fillMaxWidth().heightIn(min = 52.dp).clip(RoundedCornerShape(BtShape.md)).background(c.fill).padding(horizontal = Space.md),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm),
        ) {
            Icon(Icons.Rounded.Search, null, Modifier.size(22.dp), tint = c.textSecondary)
            Box(Modifier.weight(1f)) {
                if (m.number.isEmpty()) Text(stringResource(R.string.dial_hint), style = BtType.body, color = c.textSecondary)
                BasicTextField(
                    value = m.number, onValueChange = a.onNumber, singleLine = true,
                    textStyle = BtType.rowTitle.copy(color = c.text, fontSize = 18.sp),
                    cursorBrush = SolidColor(c.navy), modifier = Modifier.fillMaxWidth(),
                )
            }
            if (m.number.isNotEmpty()) {
                Box(Modifier.size(48.dp).clip(CircleShape).clickable(role = Role.Button) { a.onNumber("") }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.Close, stringResource(R.string.dial_delete), Modifier.size(20.dp), tint = c.textSecondary)
                }
            }
        }
        if (!m.perms.contacts.granted) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                Text(stringResource(R.string.contacts_perm_body), Modifier.weight(1f), style = BtType.caption, color = c.textSecondary)
                BtButton(stringResource(if (m.perms.contacts.blocked) R.string.perm_open_settings else R.string.perm_allow), m.perms.contacts.act, primary = false)
            }
        }
        m.suggestions.take(4).forEach { s ->
            Row(
                Modifier.fillMaxWidth().heightIn(min = 52.dp).clip(RoundedCornerShape(BtShape.sm))
                    .clickable { s.numaralar.firstOrNull()?.let(a.onNumber) },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md),
            ) {
                Avatar(s.ad, 40)
                Column(Modifier.weight(1f)) {
                    Text(s.ad, style = BtType.rowTitle, color = c.text, maxLines = 1)
                    Text(s.numaralar.firstOrNull().orEmpty(), style = BtType.caption, color = c.textSecondary, maxLines = 1)
                }
            }
        }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.sm)) {
            KEYS.chunked(3).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    row.forEach { (d, l) -> KeyButton(d, l) { a.onNumber(m.number + d) } }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                Spacer(Modifier.size(72.dp))
                Box(
                    Modifier.size(72.dp).clip(CircleShape).background(if (valid || !m.perms.call.granted) c.up else c.fill)
                        .clickable(enabled = valid || !m.perms.call.granted, role = Role.Button, onClick = a.onDial),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.Call, stringResource(R.string.dial_call), Modifier.size(30.dp), tint = if (valid || !m.perms.call.granted) onStatus(c.dark) else c.textTertiary)
                }
                DeleteKey(m.number.isNotEmpty(), { a.onNumber(m.number.dropLast(1)) }, { a.onNumber("") })
            }
        }
        if (!m.perms.call.granted) {
            Text(stringResource(R.string.dial_perm_body), style = BtType.caption, color = c.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun KeyButton(digit: String, letters: String, onClick: () -> Unit) {
    val c = MaterialTheme.bt
    Box(
        Modifier.size(72.dp).clip(CircleShape).background(c.fill).clickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(digit, style = BtType.keypad, color = c.text)
            Text(letters.ifEmpty { " " }, style = BtType.micro, color = c.textSecondary)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DeleteKey(enabled: Boolean, onClick: () -> Unit, onLongClick: () -> Unit) {
    val c = MaterialTheme.bt
    Box(
        Modifier.size(72.dp).clip(CircleShape).combinedClickable(enabled = enabled, role = Role.Button, onClick = onClick, onLongClick = onLongClick),
        contentAlignment = Alignment.Center,
    ) {
        if (enabled) Icon(BtIcons.Backspace, stringResource(R.string.dial_delete), Modifier.size(28.dp), tint = c.textSecondary)
    }
}

@Composable
private fun RecentsCard(m: PhoneUiModel, a: PhoneActions) {
    val c = MaterialTheme.bt
    val ctx = LocalContext.current
    BtCard {
        SectionLabel(stringResource(R.string.recent_title))
        if (!m.perms.callLog.granted) {
            EmptyState(
                Icons.Rounded.Lock, stringResource(R.string.recent_perm_title), stringResource(R.string.recent_perm_body),
                action = stringResource(if (m.perms.callLog.blocked) R.string.perm_open_settings else R.string.perm_allow),
                onAction = m.perms.callLog.act,
            )
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                SegmentPill(stringResource(R.string.recent_all), !m.missedOnly, Modifier.weight(1f)) { a.onMissedOnly(false) }
                SegmentPill(stringResource(R.string.recent_missed), m.missedOnly, Modifier.weight(1f)) { a.onMissedOnly(true) }
            }
            if (m.recents.isEmpty()) {
                Text(stringResource(R.string.recent_empty), style = BtType.body, color = c.textSecondary, modifier = Modifier.padding(vertical = Space.sm))
            }
            m.recents.take(15).forEach { e ->
                val missed = e.yon == "cevapsiz"
                val who = e.kisiAdi?.takeIf { it.isNotBlank() } ?: e.numara.ifBlank { stringResource(R.string.call_unknown) }
                val kind = stringResource(
                    when (e.yon) { "gelen" -> R.string.log_incoming; "giden" -> R.string.log_outgoing; else -> R.string.log_missed },
                )
                val sub = if (!missed && e.sureSn > 0) {
                    kind + " · " + if (e.sureSn >= 60) stringResource(R.string.dur_min, e.sureSn / 60) else stringResource(R.string.dur_sec, e.sureSn)
                } else kind
                val ms = e.zaman * 1000
                val whenText = if (DateUtils.isToday(ms)) DateUtils.formatDateTime(ctx, ms, DateUtils.FORMAT_SHOW_TIME)
                else DateUtils.formatDateTime(ctx, ms, DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_ABBREV_MONTH)
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 56.dp).clip(RoundedCornerShape(BtShape.sm)).clickable { a.onNumber(e.numara) },
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md),
                ) {
                    Avatar(who, 40)
                    Column(Modifier.weight(1f)) {
                        Text(who, style = BtType.rowTitle, color = if (missed) c.down else c.text, maxLines = 1)
                        Text(sub, style = BtType.caption, color = c.textSecondary, maxLines = 1)
                    }
                    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        val icon: ImageVector = if (missed) BtIcons.CallEnd else Icons.Rounded.Call
                        Icon(icon, null, Modifier.size(18.dp), tint = if (missed) c.down else if (e.yon == "gelen") c.up else c.accentText)
                        Text(whenText, style = BtType.caption, color = c.textSecondary, maxLines = 1)
                    }
                }
            }
        }
    }
}

@Composable
private fun SegmentPill(text: String, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val c = MaterialTheme.bt
    Box(
        modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(24.dp)).background(if (selected) c.navy else c.fill)
            .clickable(role = Role.RadioButton, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = BtType.rowTitle, color = if (selected) c.onNavy else c.text)
    }
}
