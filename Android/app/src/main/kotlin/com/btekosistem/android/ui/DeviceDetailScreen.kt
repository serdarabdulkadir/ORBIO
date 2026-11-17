package com.btekosistem.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Slider
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.btekosistem.android.R
import com.btekosistem.android.protocol.ListeningMode
import com.btekosistem.android.protocol.NoiseScene
import com.btekosistem.android.protocol.QcyCapability
import com.btekosistem.android.protocol.QcyCustomEq
import com.btekosistem.android.protocol.QcyEqPreset
import com.btekosistem.android.protocol.QcyKeyFunction
import com.btekosistem.android.protocol.QcyTouchGesture
import com.btekosistem.android.protocol.QcyTouchSide
import com.btekosistem.android.protocol.isEnabledFor
import com.btekosistem.android.protocol.QcyNoise
import com.btekosistem.android.protocol.isVerifiedFor
import com.btekosistem.android.ui.theme.BtShape
import com.btekosistem.android.ui.theme.BtType
import com.btekosistem.android.ui.theme.Space
import com.btekosistem.android.ui.theme.bt

class DeviceDetailActions(
    val back: () -> Unit = {},
    val setMode: (ListeningMode) -> Unit = {},
    val setScene: (NoiseScene) -> Unit = {},
    val setTransparency: (Int) -> Unit = {},
    val setEqPreset: (QcyEqPreset) -> Unit = {},
    val setTouch: (QcyTouchSide, QcyTouchGesture, QcyKeyFunction) -> Unit = { _, _, _ -> },
    val applyEq: (List<Int>) -> Unit = {},
    val setWearing: (Boolean) -> Unit = {},
    val setEarDetection: (Boolean) -> Unit = {},
    val setGameMode: (Boolean) -> Unit = {},
    val dismissError: () -> Unit = {},
    val forget: () -> Unit = {},
)

/** Mac "Ayarlar > Cihaz" sayfasinin karsiligi; ayni bolumler ve metinler. MeloBuds Pro (TWS) profili. */
@Composable
fun DeviceDetailScreen(state: HomeState, device: FoundDevice, actions: DeviceDetailActions, contentPadding: PaddingValues) {
    val c = MaterialTheme.bt
    val q = state.device
    val connected = state.link == Link.CONNECTED && state.ready
    val enabled = connected && !state.busy
    var confirmForget by remember { mutableStateOf(false) }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(
            start = Space.lg, end = Space.lg,
            top = contentPadding.calculateTopPadding() + Space.sm,
            bottom = contentPadding.calculateBottomPadding() + Space.lg,
        ),
        verticalArrangement = Arrangement.spacedBy(Space.md),
    ) {
        val backLabel = stringResource(R.string.detail_back)
        Row(
            Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(24.dp))
                .clickable(role = Role.Button, onClick = actions.back).semantics { contentDescription = backLabel }
                .padding(end = Space.lg),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm),
        ) {
            Icon(Icons.AutoMirrored.Rounded.ArrowBack, null, Modifier.size(24.dp), tint = c.text)
            Text(stringResource(R.string.home_title), style = BtType.rowTitle, color = c.text)
        }
        state.error?.let { ErrorBanner(it, actions.dismissError) }

        Text(stringResource(R.string.controls_title), style = BtType.pageTitle, color = c.text)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            StatusDot(if (connected) c.up else c.textTertiary)
            Text(
                (device.name ?: stringResource(R.string.device_default_name)) + " · " +
                    stringResource(if (connected && state.via == ControlVia.MAC) R.string.link_via_mac else if (connected) R.string.link_connected else R.string.link_idle),
                style = BtType.caption, color = c.textSecondary,
            )
        }
        if (!connected) Text(stringResource(R.string.detail_need_connection), style = BtType.caption, color = c.textSecondary)

        // Dokunmatik kontroller (APK'dan okundu)
        if (QcyCapability.TOUCH_KEYS.isEnabledFor(TWS)) {
            SectionLabel(stringResource(R.string.touch_title))
            BtCard {
                listOf(QcyTouchSide.LEFT to R.string.touch_left, QcyTouchSide.RIGHT to R.string.touch_right).forEachIndexed { i, (side, title) ->
                    if (i > 0) HorizontalDivider(color = c.separator)
                    Text(stringResource(title), style = BtType.rowTitle, color = c.text)
                    listOf(
                        QcyTouchGesture.SINGLE to R.string.touch_single,
                        QcyTouchGesture.DOUBLE to R.string.touch_double,
                        QcyTouchGesture.TRIPLE to R.string.touch_triple,
                    ).forEach { (gesture, label) ->
                        DropdownLine(
                            stringResource(label),
                            q.touchKeys?.function(side, gesture)?.let { stringResource(keyLabel(it)) } ?: stringResource(R.string.dash),
                            QcyKeyFunction.entries.map { it to stringResource(keyLabel(it)) },
                            enabled && q.touchKeys != null,
                        ) { actions.setTouch(side, gesture, it) }
                    }
                }
                if (q.touchKeys == null) Note(stringResource(R.string.touch_unread))
            }
        }

        // Algilama ve oyun
        SectionLabel(stringResource(R.string.detail_detect_title))
        BtCard {
            val wearing = q.wearing
            if (wearing != null) {
                SwitchLine(R.string.wear_title, wearing.enabled, enabled) { actions.setWearing(it) }
                Note(stringResource(R.string.detail_wear_note))
            } else if (QcyCapability.EAR_DETECTION.isVerifiedFor(TWS)) {
                SwitchLine(R.string.wear_title, q.earDetection ?: false, enabled && q.earDetection != null) { actions.setEarDetection(it) }
                if (q.earDetection == null) Note(stringResource(R.string.detail_unread))
            }
            if (QcyCapability.GAME_MODE.isVerifiedFor(TWS)) {
                HorizontalDivider(color = c.separator)
                SwitchLine(R.string.detail_game, q.gameMode ?: false, enabled && q.gameMode != null) { actions.setGameMode(it) }
                if (q.gameMode == null) Note(stringResource(R.string.detail_unread))
            }
        }

        BtCard { InfoNote(stringResource(R.string.detail_storage_note)) }

        // Unut
        BtButton(stringResource(R.string.detail_forget), { confirmForget = true }, Modifier.fillMaxWidth(), primary = false)
        Note(stringResource(R.string.detail_forget_note))
    }

    if (confirmForget) {
        val name = device.name ?: stringResource(R.string.device_default_name)
        AlertDialog(
            onDismissRequest = { confirmForget = false },
            containerColor = c.card,
            title = { Text(stringResource(R.string.detail_forget_q, name), style = BtType.rowTitle, color = c.text) },
            text = { Text(stringResource(R.string.detail_forget_note), style = BtType.body, color = c.textSecondary) },
            confirmButton = {
                TextButton({ confirmForget = false; actions.forget() }, Modifier.heightIn(min = 48.dp)) {
                    Text(stringResource(R.string.detail_forget_do), color = c.down)
                }
            },
            dismissButton = {
                TextButton({ confirmForget = false }, Modifier.heightIn(min = 48.dp)) {
                    Text(stringResource(R.string.detail_cancel), color = c.text)
                }
            },
        )
    }
}

/** MeloBuds Pro bir TWS kulaklik; dogrulama bu profile gore. */
internal const val TWS = true

private fun keyLabel(f: QcyKeyFunction) = when (f) {
    QcyKeyFunction.NONE -> R.string.key_none
    QcyKeyFunction.PLAY_PAUSE -> R.string.key_play_pause
    QcyKeyFunction.PREVIOUS -> R.string.key_previous
    QcyKeyFunction.NEXT -> R.string.key_next
    QcyKeyFunction.ASSISTANT -> R.string.key_assistant
    QcyKeyFunction.VOLUME_UP -> R.string.key_volume_up
    QcyKeyFunction.VOLUME_DOWN -> R.string.key_volume_down
    QcyKeyFunction.GAME_MODE -> R.string.key_game_mode
}

@Composable
private fun Note(text: String) {
    Text(text, style = BtType.caption, color = MaterialTheme.bt.textSecondary)
}

@Composable
private fun InfoNote(text: String) {
    Text(text, style = BtType.body, color = MaterialTheme.bt.textSecondary)
}

/** Etiket + secili deger; dokununca acilir menu (dropdown). */
@Composable
private fun <T> DropdownLine(label: String, value: String, options: List<Pair<T, String>>, enabled: Boolean, onSelect: (T) -> Unit) {
    val c = MaterialTheme.bt
    var open by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(BtShape.md))
                .clickable(enabled = enabled, role = Role.DropdownList) { open = true },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md),
        ) {
            Text(label, Modifier.weight(1f), style = BtType.rowTitle, color = if (enabled) c.text else c.textTertiary)
            Text(value, style = BtType.body, color = c.textSecondary, textAlign = TextAlign.End)
            Icon(BtIcons.ChevronRight, null, Modifier.size(20.dp), tint = c.textSecondary)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { (v, text) ->
                DropdownMenuItem(text = { Text(text) }, onClick = { open = false; onSelect(v) })
            }
        }
    }
}

@Composable
internal fun SwitchLine(title: Int, checked: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    val c = MaterialTheme.bt
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
        Text(stringResource(title), Modifier.weight(1f), style = BtType.rowTitle, color = if (enabled) c.text else c.textTertiary)
        BtPillSwitch(checked, enabled, onChange)
    }
}
