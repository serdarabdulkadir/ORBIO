package com.btekosistem.android.ui

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.provider.Settings
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.btekosistem.android.R
import com.btekosistem.android.audio.AudioLink
import com.btekosistem.android.audio.AudioSnapshot
import com.btekosistem.android.audio.BondState
import com.btekosistem.android.peer.LocalMedia
import com.btekosistem.android.peer.MacPhase
import com.btekosistem.android.peer.MediaBridge
import com.btekosistem.android.peer.MediaCmd
import com.btekosistem.android.peer.MediaTarget
import com.btekosistem.android.peer.VolState
import com.btekosistem.android.peer.PeerManager
import com.btekosistem.android.protocol.QcyCapability
import com.btekosistem.android.protocol.QcyCustomEq
import com.btekosistem.android.protocol.QcyEqPreset
import com.btekosistem.android.protocol.isEnabledFor
import com.btekosistem.android.protocol.isVerifiedFor
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.btekosistem.android.protocol.ListeningMode
import com.btekosistem.android.protocol.NoiseScene
import com.btekosistem.android.protocol.QcyNoise
import com.btekosistem.android.ui.theme.BtShape
import com.btekosistem.android.ui.theme.BtType
import com.btekosistem.android.ui.theme.Space
import com.btekosistem.android.ui.theme.bt
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

data class HeadsetActions(
    val connectControl: (String) -> Unit = {},
    val disconnectControl: () -> Unit = {},
    val takeControl: () -> Unit = {},
    val giveControl: () -> Unit = {},
    val setMode: (ListeningMode) -> Unit = {},
    val setScene: (NoiseScene) -> Unit = {},
    val setTransparency: (Int) -> Unit = {},
    val setWearing: (Boolean) -> Unit = {},
    val dismissError: () -> Unit = {},
    val pair: () -> Unit = {},
    val connectAudio: () -> Unit = {},
    val openBtSettings: () -> Unit = {},
    val setVolume: (Int) -> Unit = {},
    val toggleMute: () -> Unit = {},
    val setAutoSwitch: (Boolean) -> Unit = {},
    val openDetail: () -> Unit = {},
    val setEqPreset: (QcyEqPreset) -> Unit = {},
    val setGameMode: (Boolean) -> Unit = {},
    val setEarDetection: (Boolean) -> Unit = {},
    val applyEq: (List<Int>) -> Unit = {},
    val mediaCommand: (MediaTarget, MediaCmd) -> Unit = { _, _ -> },
    val openMediaAccess: () -> Unit = {},
    val setMacVolume: (Int?, Boolean?) -> Unit = { _, _ -> },
)

data class VolumeUi(val volume: Int = 7, val max: Int = 15, val muted: Boolean = false, val mac: VolState? = null)

/** Durum tutan sarmalayici: ses yoneticisi, ses profili durumu ve ayarlar burada toplanir. */
@Composable
fun HomeScreen(state: HomeState, vm: MainViewModel, contentPadding: PaddingValues) {
    val ctx = LocalContext.current
    val mgr = remember { PeerManager.get(ctx) }
    val audio by mgr.earbud.audio.collectAsStateWithLifecycle()
    val settings by mgr.store.settings.collectAsStateWithLifecycle()
    val am = remember { ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    val max = remember { am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1) }
    var vol by remember { mutableIntStateOf(am.getStreamVolume(AudioManager.STREAM_MUSIC)) }
    var muted by remember { mutableStateOf(am.isStreamMute(AudioManager.STREAM_MUSIC)) }
    LaunchedEffect(Unit) {
        mgr.earbud.start()
        while (true) {
            vol = am.getStreamVolume(AudioManager.STREAM_MUSIC)
            muted = am.isStreamMute(AudioManager.STREAM_MUSIC)
            delay(1000)
        }
    }
    val actions = remember(vm, mgr) {
        HeadsetActions(
            connectControl = vm::connect, disconnectControl = vm::disconnect, takeControl = vm::takeControlFromMac, giveControl = vm::giveControlToMac, setMode = vm::setMode, setScene = vm::setScene, setTransparency = vm::setTransparency,
            setWearing = vm::setWearing, dismissError = vm::dismissError,
            pair = { mgr.earbud.pair() }, connectAudio = { mgr.earbud.connectAudio() },
            openBtSettings = { ctx.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) },
            setVolume = { v ->
                am.setStreamVolume(AudioManager.STREAM_MUSIC, v, 0)
                vol = v
            },
            toggleMute = {
                am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_TOGGLE_MUTE, 0)
                muted = am.isStreamMute(AudioManager.STREAM_MUSIC)
            },
            setAutoSwitch = { on -> mgr.store.update { it.copy(autoSwitch = on) } },
            setEqPreset = vm::setEqPreset, applyEq = vm::applyEq,
            setGameMode = vm::setGameMode, setEarDetection = vm::setEarDetection,
            mediaCommand = { t, cmd -> mgr.media.command(t, cmd) },
            setMacVolume = vm::setMacVolume,
            openMediaAccess = { ctx.startActivity(MediaBridge.accessSettingsIntent().addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) },
        )
    }
    val media by vm.media.collectAsStateWithLifecycle()
    val macVol by vm.volumeMac.collectAsStateWithLifecycle()
    val mac by mgr.state.collectAsStateWithLifecycle()
    var mediaAccess by remember { mutableStateOf(MediaBridge.hasAccess(ctx)) }
    LifecycleResumeEffect(Unit) {
        mediaAccess = MediaBridge.hasAccess(ctx)
        mgr.media.refresh()
        onPauseOrDispose { }
    }
    var detail by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(false) }
    val selected = state.selected
    if (detail && state.link != Link.CONNECTED) detail = false
    if (detail && selected != null && state.link == Link.CONNECTED) {
        androidx.activity.compose.BackHandler { detail = false }
        DeviceDetailScreen(
            state, selected,
            DeviceDetailActions(
                back = { detail = false }, setMode = vm::setMode, setScene = vm::setScene, setTransparency = vm::setTransparency,
                setEqPreset = vm::setEqPreset, setWearing = vm::setWearing, setEarDetection = vm::setEarDetection,
                setGameMode = vm::setGameMode, setTouch = vm::setTouch, applyEq = vm::applyEq, dismissError = vm::dismissError,
                forget = { detail = false; vm.forget(selected.key) },
            ),
            contentPadding,
        )
    } else {
        HeadsetContent(
            state, audio, VolumeUi(vol, max, muted, macVol), settings.autoSwitch, actions.copy(openDetail = { detail = true }), contentPadding,
            media = media, mediaAccess = mediaAccess, macConnected = mac.phase == MacPhase.CONNECTED,
        )
    }
}

@Composable
fun HeadsetContent(
    state: HomeState, audio: AudioSnapshot, volume: VolumeUi, autoSwitch: Boolean,
    actions: HeadsetActions, contentPadding: PaddingValues,
    media: LocalMedia = LocalMedia(), mediaAccess: Boolean = true, macConnected: Boolean = false,
) {
    Column(Modifier.fillMaxSize()) {
        HeadsetList(state, audio, volume, autoSwitch, actions, contentPadding, Modifier.weight(1f))
        MiniPlayer(
            media, mediaAccess, macConnected, actions.mediaCommand, actions.openMediaAccess,
            Modifier.padding(start = Space.lg, end = Space.lg, bottom = Space.sm, top = Space.xs),
        )
    }
}

@Composable
private fun HeadsetList(
    state: HomeState, audio: AudioSnapshot, volume: VolumeUi, autoSwitch: Boolean,
    actions: HeadsetActions, contentPadding: PaddingValues, modifier: Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(
            start = Space.lg, end = Space.lg,
            top = contentPadding.calculateTopPadding() + Space.lg,
            bottom = contentPadding.calculateBottomPadding() + Space.lg,
        ),
        verticalArrangement = Arrangement.spacedBy(Space.md),
    ) {
        val active = state.selected ?: state.devices.firstOrNull()
        item { HomeHeader(active, state) }
        state.error?.let { err -> item { ErrorBanner(err, actions.dismissError) } }
        if (active == null) {
            item {
                BtCard {
                    EmptyState(
                        BtIcons.Bluetooth, stringResource(R.string.home_searching_title), stringResource(R.string.home_searching_body),
                    )
                }
            }
        } else {
            item { HeroCard(active, state, audio) }
        }
        state.apple?.let { a -> item(key = "apple") { AirPodsCard(a, state.now) } }
        // Etkin cihazin baglanti adimlari / eylemleri; diger cihazlar tam kartla listelenir.
        items(state.devices, key = { it.key }) { device -> DeviceCard(device, state, audio, actions, compact = device.key == active?.key) }
        if (active != null) {
            if (audio.connectFailed && audio.address.equals(active.advertisement.controlAddress, ignoreCase = true)) {
                item { AudioHelpCard(actions.openBtSettings) }
            }
            val on = state.selected != null && state.link == Link.CONNECTED
            item { NoiseCard(state, volume, actions, on, active.key) }
            item { EqualizerCard(state, actions, on) }
            item { ControlsCard(state, actions, on) }
            if (on) item { GeneralCard(volume, autoSwitch, actions) }
        }
    }
}

/** Ust baslik: cihaz adi (kalin) + sagda kucuk durum hapi. */
@Composable
private fun HomeHeader(device: FoundDevice?, state: HomeState) {
    val c = MaterialTheme.bt
    val connected = state.link == Link.CONNECTED
    val status = when (state.link) {
        Link.CONNECTED -> R.string.link_connected
        Link.CONNECTING -> R.string.link_connecting
        Link.IDLE -> R.string.link_idle
    }
    Row(Modifier.fillMaxWidth().padding(bottom = Space.xs), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
        Text(
            device?.name ?: stringResource(R.string.home_title), Modifier.weight(1f),
            style = BtType.pageTitle, color = c.text, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
        )
        if (device != null) {
            Row(
                Modifier.clip(CircleShape).background(c.card).padding(horizontal = Space.md, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                StatusDot(if (connected) c.up else c.textTertiary, 7.dp)
                Text(stringResource(status), style = BtType.caption, color = c.textSecondary, maxLines = 1)
            }
        }
    }
}

@Composable
private fun HeroCard(device: FoundDevice, state: HomeState, audioAll: AudioSnapshot) {
    val c = MaterialTheme.bt
    val adv = device.advertisement
    val isSelected = state.selectedKey == device.key
    val control = if (isSelected) state.link else Link.IDLE
    val audio: AudioSnapshot? = if (adv.controlAddress.equals(audioAll.address, ignoreCase = true)) audioAll else null
    val audioWord = when (audio?.link) {
        AudioLink.CONNECTED -> R.string.st_audio_connected
        AudioLink.CONNECTING -> R.string.st_audio_connecting
        AudioLink.PAIRING -> R.string.st_audio_pairing
        AudioLink.NOT_PAIRED -> R.string.st_audio_not_paired
        AudioLink.IDLE -> R.string.st_audio_idle
        null -> R.string.st_audio_unknown
    }
    Box(Modifier.fillMaxWidth()) {
        // Kulakliklar kartin ust kenarina tasar: kart 78 dp asagidan baslar.
        BtCard(Modifier.padding(top = 78.dp)) {
            Spacer(Modifier.height(54.dp))
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                Text(device.name ?: stringResource(R.string.device_default_name), style = BtType.cardTitle, color = c.text, maxLines = 2, textAlign = TextAlign.Center)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                    StatusDot(if (audio?.link == AudioLink.CONNECTED) c.up else c.textTertiary)
                    Text(stringResource(audioWord), style = BtType.rowTitle, color = c.text, textAlign = TextAlign.Center)
                }
                Text(linkSummary(audio, control, state.via), style = BtType.caption, color = c.textSecondary, textAlign = TextAlign.Center)
                if (!device.bonded) Chip(stringResource(R.string.device_nearby), c.textSecondary, c.fill)
            }
            Row(Modifier.fillMaxWidth().padding(top = Space.xs), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.Top) {
                BatteryBadge(stringResource(R.string.battery_left_short), stringResource(R.string.battery_left), adv.left, adv.leftCharging, Modifier.weight(1f))
                // Kutu pili her modelde yok: okuma yoksa gosterme.
                if (adv.caseLevel != null) {
                    BatteryBadge(stringResource(R.string.battery_case_short), stringResource(R.string.battery_case), adv.caseLevel, adv.caseCharging, Modifier.weight(1f))
                }
                BatteryBadge(stringResource(R.string.battery_right_short), stringResource(R.string.battery_right), adv.right, adv.rightCharging, Modifier.weight(1f))
            }
            val ago = ((state.now - device.seenAt) / 1000).toInt().coerceAtLeast(0)
            Text(
                if (ago < 3) stringResource(R.string.battery_updated_now) else stringResource(R.string.battery_updated_ago, ago),
                Modifier.fillMaxWidth(), style = BtType.caption, color = c.textTertiary, textAlign = TextAlign.Center,
            )
        }
        EarbudsHero(audio?.link == AudioLink.CONNECTED, Modifier.align(Alignment.TopCenter))
    }
}

@Composable
private fun linkSummary(audio: AudioSnapshot?, control: Link, via: ControlVia): String {
    val audioWord = when (audio?.link) {
        AudioLink.CONNECTED -> R.string.audio_connected
        AudioLink.CONNECTING -> R.string.audio_connecting
        AudioLink.PAIRING -> R.string.audio_pairing
        AudioLink.NOT_PAIRED -> R.string.audio_not_paired
        AudioLink.IDLE -> R.string.audio_idle
        null -> R.string.audio_unknown
    }
    val ctlWord = when (control) {
        Link.CONNECTED -> if (via == ControlVia.MAC) R.string.ctl_via_mac else R.string.ctl_ready
        Link.CONNECTING -> R.string.ctl_connecting
        Link.IDLE -> R.string.ctl_off
    }
    return stringResource(R.string.link_summary, stringResource(audioWord), stringResource(ctlWord))
}

@Composable
internal fun ErrorBanner(error: UiError, onDismiss: () -> Unit) {
    val c = MaterialTheme.bt
    val text = when (error) {
        UiError.CONNECT -> R.string.err_connect
        UiError.SERVICE -> R.string.err_service
        UiError.WRITE -> R.string.err_write
        UiError.KEYS_UNREAD -> R.string.err_keys_unread
    }
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(BtShape.lg)).background(c.downBg)
            .clickable(onClick = onDismiss).padding(Space.lg),
        horizontalArrangement = Arrangement.spacedBy(Space.md), verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.Close, null, Modifier.size(20.dp), tint = c.down)
        Text(stringResource(text), Modifier.weight(1f), style = BtType.body, color = c.down)
    }
}

private enum class StepState { DONE, ACTIVE, TODO }

@Composable
private fun StepRow(pair: StepState, audio: StepState, control: StepState) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
        Step(1, stringResource(R.string.step_pair), pair, Modifier.weight(1f))
        Step(2, stringResource(R.string.step_audio), audio, Modifier.weight(1f))
        Step(3, stringResource(R.string.step_control), control, Modifier.weight(1f))
    }
}

@Composable
private fun Step(n: Int, label: String, st: StepState, modifier: Modifier) {
    val c = MaterialTheme.bt
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.xs)) {
        Box(
            Modifier.size(28.dp).clip(CircleShape).background(
                when (st) { StepState.DONE -> c.up; StepState.ACTIVE -> c.navy; StepState.TODO -> c.fill },
            ),
            contentAlignment = Alignment.Center,
        ) {
            if (st == StepState.DONE) Icon(Icons.Rounded.Check, null, Modifier.size(18.dp), tint = c.card)
            else Text(n.toString(), style = BtType.caption, color = if (st == StepState.ACTIVE) c.onNavy else c.textSecondary)
        }
        Text(label, style = BtType.caption, color = if (st == StepState.TODO) c.textSecondary else c.text, textAlign = TextAlign.Center)
    }
}

@Composable
private fun DeviceCard(device: FoundDevice, state: HomeState, audioAll: AudioSnapshot, actions: HeadsetActions, compact: Boolean) {
    val c = MaterialTheme.bt
    val isSelected = state.selectedKey == device.key
    val control = if (isSelected) state.link else Link.IDLE
    val audio: AudioSnapshot? = if (device.advertisement.controlAddress.equals(audioAll.address, ignoreCase = true)) audioAll else null
    val reduce = rememberReduceMotion()
    BtCard(Modifier.animateContentSize(motion(reduce, 200))) {
        if (!compact) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
                    Text(device.name ?: stringResource(R.string.device_default_name), style = BtType.cardTitle, color = c.text, maxLines = 2)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                        StatusDot(if (audio?.link == AudioLink.CONNECTED) c.up else c.textTertiary)
                        Text(linkSummary(audio, control, state.via), style = BtType.caption, color = c.textSecondary)
                    }
                }
                Chip(
                    stringResource(if (device.bonded) R.string.device_paired else R.string.device_nearby),
                    fg = if (device.bonded) c.accentText else c.textSecondary, bg = c.fill,
                )
            }
        }
        val allDone = audio?.link == AudioLink.CONNECTED && control == Link.CONNECTED
        if (audio != null) {
            if (!(compact && allDone)) {
                StepRow(
                    when (audio.link) {
                        AudioLink.NOT_PAIRED -> StepState.TODO
                        AudioLink.PAIRING -> StepState.ACTIVE
                        else -> StepState.DONE
                    },
                    when (audio.link) {
                        AudioLink.CONNECTED -> StepState.DONE
                        AudioLink.CONNECTING -> StepState.ACTIVE
                        else -> StepState.TODO
                    },
                    when (control) {
                        Link.CONNECTED -> StepState.DONE
                        Link.CONNECTING -> StepState.ACTIVE
                        Link.IDLE -> StepState.TODO
                    },
                )
            }
            if (audio.pairFailed) Text(stringResource(R.string.pair_failed), style = BtType.caption, color = c.down)
            val modifier = Modifier.fillMaxWidth()
            when (audio.link) {
                AudioLink.NOT_PAIRED -> BtButton(stringResource(R.string.act_pair), actions.pair, modifier)
                AudioLink.PAIRING -> BtButton(stringResource(R.string.act_pairing), {}, modifier, enabled = false)
                AudioLink.IDLE -> BtButton(stringResource(R.string.act_audio_connect), actions.connectAudio, modifier)
                AudioLink.CONNECTING -> BtButton(stringResource(R.string.act_audio_connecting), {}, modifier, enabled = false)
                AudioLink.CONNECTED -> {}
            }
            if (audio.link == AudioLink.CONNECTED) ControlButton(control, device.key, actions, modifier)
            else if (audio.link != AudioLink.PAIRING && control == Link.IDLE) {
                BtButton(stringResource(R.string.act_ctl_open), { actions.connectControl(device.key) }, modifier, primary = false)
            }
        } else {
            ControlButton(control, device.key, actions, Modifier.fillMaxWidth())
        }
        // Mac oturumu varken sahiplik: oturum yokken gizli.
        if (isSelected && state.macSession && control == Link.CONNECTED) {
            if (state.via == ControlVia.MAC) BtButton(stringResource(R.string.act_ctl_take), actions.takeControl, Modifier.fillMaxWidth(), primary = false)
            else BtButton(stringResource(R.string.act_ctl_give), actions.giveControl, Modifier.fillMaxWidth(), primary = false)
        }
    }
}

@Composable
private fun ControlButton(control: Link, key: String, actions: HeadsetActions, modifier: Modifier) {
    when (control) {
        Link.IDLE -> BtButton(stringResource(R.string.act_ctl_open), { actions.connectControl(key) }, modifier)
        Link.CONNECTING -> BtButton(stringResource(R.string.act_ctl_connecting), {}, modifier, enabled = false)
        Link.CONNECTED -> BtButton(stringResource(R.string.act_ctl_close), actions.disconnectControl, modifier, primary = false)
    }
}

@Composable
private fun AudioHelpCard(openSettings: () -> Unit) {
    BtCard {
        EmptyState(
            BtIcons.Bluetooth, stringResource(R.string.help_audio_title), stringResource(R.string.help_audio_body),
            action = stringResource(R.string.help_audio_open), onAction = openSettings,
        )
    }
}

@Composable
private fun NoiseCard(state: HomeState, volume: VolumeUi, actions: HeadsetActions, connected: Boolean, key: String) {
    val c = MaterialTheme.bt
    val reduce = rememberReduceMotion()
    val mode = state.device.mode
    val enabled = connected && state.ready && !state.busy
    val pct = volume.volume * 100 / volume.max
    val onVol = { d: Int -> actions.setVolume((volume.volume + d).coerceIn(0, volume.max)) }
    BtCard {
        Text(stringResource(R.string.noise_title), style = BtType.cardTitle, color = c.text)
        if (!connected) {
            // Bos durum: soluk kadran + tek cumle + siyah hap dugme
            Box(Modifier.alpha(0.4f)) { NoiseDial(null, false, {}, pct, false, {}) }
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.sm)) {
                Text(stringResource(R.string.ctl_off_title), style = BtType.rowTitle, color = c.text, textAlign = TextAlign.Center)
                Text(stringResource(R.string.control_off_hint), style = BtType.caption, color = c.textSecondary, textAlign = TextAlign.Center)
                if (state.link == Link.CONNECTING) {
                    BtButton(stringResource(R.string.act_ctl_connecting), {}, Modifier.sizeIn(minWidth = 200.dp), enabled = false)
                } else {
                    BtButton(stringResource(R.string.act_ctl_open), { actions.connectControl(key) }, Modifier.sizeIn(minWidth = 200.dp))
                }
            }
        } else {
            if (state.busy) LinearProgressIndicator(Modifier.fillMaxWidth().height(2.dp), color = c.navy, trackColor = c.separator)
            if (mode == null) Text(stringResource(R.string.control_reading), style = BtType.body, color = c.textSecondary)
            NoiseDial(mode, enabled, actions.setMode, pct, true, onVol)
            volume.mac?.let { MacVolumeRow(it, actions.setMacVolume) }
            if (mode == ListeningMode.SEFFAF) TransparencyControl(state.device.transparency, enabled, actions.setTransparency)
            AnimatedVisibility(
                visible = mode == ListeningMode.GURULTU_ENGELLEME,
                enter = if (reduce) EnterTransition.None else fadeIn(motion(false, 200)) + expandVertically(motion(false, 200)),
                exit = if (reduce) ExitTransition.None else fadeOut(motion(false, 150)) + shrinkVertically(motion(false, 150)),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(Space.sm)) {
                    SectionLabel(stringResource(R.string.scene_title))
                    val scroll = rememberScrollState()
                    Box(Modifier.fillMaxWidth()) {
                        Row(Modifier.horizontalScroll(scroll), horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                            NoiseScene.entries.forEach { s ->
                                ScenePill(stringResource(sceneLabel(s)), state.device.scene == s, enabled) { actions.setScene(s) }
                            }
                        }
                        if (scroll.canScrollForward) {
                            Box(
                                Modifier.align(Alignment.CenterEnd).width(36.dp).fillMaxHeight()
                                    .background(Brush.horizontalGradient(listOf(Color.Transparent, c.card))),
                            )
                        }
                    }
                    if (state.device.scene == null) {
                        Text(stringResource(R.string.scene_unknown), style = BtType.caption, color = c.textSecondary)
                    }
                }
            }
        }
    }
}

/** Hazir ayar cipleri (yatay kayar) + 10 bantli ozel ekolayzer grafigi. */
@Composable
private fun EqualizerCard(state: HomeState, actions: HeadsetActions, connected: Boolean) {
    val c = MaterialTheme.bt
    val enabled = connected && state.ready && !state.busy
    var gains by remember { mutableStateOf(List(QcyCustomEq.BAND_COUNT) { 0 }) }
    val eqA11y = stringResource(R.string.detail_eq_a11y)
    BtCard(Modifier.alpha(if (connected) 1f else 0.5f)) {
        Text(stringResource(R.string.detail_eq_title), style = BtType.cardTitle, color = c.text)
        if (QcyCapability.EQ_PRESET.isVerifiedFor(TWS)) {
            val scroll = rememberScrollState()
            Box(Modifier.fillMaxWidth()) {
                Row(
                    Modifier.horizontalScroll(scroll).semantics { contentDescription = eqA11y },
                    horizontalArrangement = Arrangement.spacedBy(Space.sm),
                ) {
                    QcyEqPreset.all.forEach { p ->
                        PresetChip(stringResource(eqPresetLabel(p)), p, state.device.eqPreset == p, enabled) { actions.setEqPreset(p) }
                    }
                }
                if (scroll.canScrollForward) {
                    Box(
                        Modifier.align(Alignment.CenterEnd).width(36.dp).fillMaxHeight()
                            .background(Brush.horizontalGradient(listOf(Color.Transparent, c.card))),
                    )
                }
            }
        }
        if (QcyCapability.EQ_CUSTOM.isEnabledFor(TWS)) {
            Text(stringResource(R.string.eq_custom_title), style = BtType.rowTitle, color = c.text)
            EqChart(gains, enabled, { gains = it })
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                BtButton(stringResource(R.string.eq_reset), { gains = List(QcyCustomEq.BAND_COUNT) { 0 } }, Modifier.weight(1f), primary = false, enabled = enabled)
                BtButton(stringResource(R.string.eq_apply), { actions.applyEq(gains) }, Modifier.weight(1f), enabled = enabled)
            }
        }
    }
}

/** Kontroller: dokunuslar (detay sayfasi), oyun modu ve kulak algilama anahtarlari, cihaz ayarlari. */
@Composable
private fun ControlsCard(state: HomeState, actions: HeadsetActions, connected: Boolean) {
    val c = MaterialTheme.bt
    val q = state.device
    val enabled = connected && state.ready && !state.busy
    BtCard(Modifier.alpha(if (connected) 1f else 0.5f)) {
        Text(stringResource(R.string.controls_title), style = BtType.cardTitle, color = c.text)
        if (QcyCapability.TOUCH_KEYS.isEnabledFor(TWS)) {
            ValueRow(stringResource(R.string.touch_title), stringResource(R.string.ctl_touch_value), connected, actions.openDetail)
            HorizontalDivider(color = c.separator)
        }
        val wearing = q.wearing
        if (wearing != null) {
            SwitchLine(R.string.wear_title, wearing.enabled, enabled) { actions.setWearing(it) }
        } else if (QcyCapability.EAR_DETECTION.isVerifiedFor(TWS)) {
            SwitchLine(R.string.wear_title, q.earDetection ?: false, enabled && q.earDetection != null) { actions.setEarDetection(it) }
        }
        if (QcyCapability.GAME_MODE.isVerifiedFor(TWS)) {
            HorizontalDivider(color = c.separator)
            SwitchLine(R.string.detail_game, q.gameMode ?: false, enabled && q.gameMode != null) { actions.setGameMode(it) }
        }
        HorizontalDivider(color = c.separator)
        ValueRow(stringResource(R.string.detail_open), "", connected, actions.openDetail)
    }
}

private fun eqPresetLabel(b: QcyEqPreset) = when (b) {
    QcyEqPreset.DEFAULT -> R.string.eq_default
    QcyEqPreset.POP -> R.string.eq_pop
    QcyEqPreset.BASS -> R.string.eq_bass
    QcyEqPreset.ROCK -> R.string.eq_rock
    QcyEqPreset.SOFT -> R.string.eq_soft
    QcyEqPreset.CLASSIC -> R.string.eq_classic
}

/** Kullanicinin kulakligi 5 kademeli: arayuz 1..5 gosterir/yazar (cihazdan 6-8 gelirse 5'e sikistirilir). */
private const val UI_TRANSPARENCY_MAX = 5

/** Mac bagliyken kadranin altinda: Mac sesi kaydirici + sessiz dugmesi. */
@Composable
private fun MacVolumeRow(mac: VolState, onSet: (Int?, Boolean?) -> Unit) {
    val c = MaterialTheme.bt
    var drag by remember { mutableStateOf<Float?>(null) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
        Text(stringResource(R.string.vol_mac), style = BtType.caption, color = c.textSecondary)
        Slider(
            value = drag ?: mac.level.toFloat(), onValueChange = { drag = it },
            onValueChangeFinished = { drag?.let { onSet(it.roundToInt(), null) }; drag = null },
            valueRange = 0f..100f, modifier = Modifier.weight(1f),
            colors = SliderDefaults.colors(thumbColor = c.navy, activeTrackColor = c.navy, inactiveTrackColor = c.fill),
        )
        ScenePill(stringResource(R.string.act_mute), mac.muted, true) { onSet(null, !mac.muted) }
    }
}

@Composable
private fun TransparencyControl(level: Int?, enabled: Boolean, onChange: (Int) -> Unit) {
    val c = MaterialTheme.bt
    var local by remember { mutableIntStateOf((level ?: QcyNoise.TRANSPARENCY_DEFAULT).coerceIn(QcyNoise.TRANSPARENCY_MIN, UI_TRANSPARENCY_MAX)) }
    // Cihaz bildirimi gelince kaydiriciyi onunla guncelle.
    LaunchedEffect(level) { if (level != null) local = level.coerceIn(QcyNoise.TRANSPARENCY_MIN, UI_TRANSPARENCY_MAX) }
    Column(verticalArrangement = Arrangement.spacedBy(Space.sm)) {
        SectionLabel(stringResource(R.string.transp_title))
        PillSlider(local, QcyNoise.TRANSPARENCY_MIN, UI_TRANSPARENCY_MAX, enabled, { local = it; onChange(it) })
    }
}

@Composable
private fun ScenePill(text: String, selected: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val c = MaterialTheme.bt
    Box(
        Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(22.dp))
            .background(if (selected) c.navy else c.fill)
            .clickable(enabled = enabled, role = Role.RadioButton, onClick = onClick)
            .padding(horizontal = Space.lg),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = BtType.rowTitle, color = if (selected) c.onNavy else if (enabled) c.text else c.textTertiary, maxLines = 1)
    }
}

private fun sceneLabel(s: NoiseScene) = when (s) {
    NoiseScene.UYARLANIR -> R.string.scene_adaptive
    NoiseScene.KAPALI_ALAN -> R.string.scene_quiet
    NoiseScene.YOLCULUK -> R.string.scene_commute
    NoiseScene.GURULTULU -> R.string.scene_noisy
    NoiseScene.RUZGAR_KARSITI -> R.string.scene_wind
}

@Composable
private fun GeneralCard(volume: VolumeUi, autoSwitch: Boolean, actions: HeadsetActions) {
    val c = MaterialTheme.bt
    BtCard {
        SwitchLine(R.string.act_auto, autoSwitch, true) { actions.setAutoSwitch(it) }
        HorizontalDivider(color = c.separator)
        SwitchLine(R.string.act_mute, volume.muted, true) { actions.toggleMute() }
    }
}

/** AirPods / Beats: Proximity Pairing reklamindan yalniz okunur bilgi (Android'de AAP kontrol kanali guvenilir degil). */
@Composable
private fun AirPodsCard(sighting: com.btekosistem.android.ble.AppleSighting, now: Long) {
    val c = MaterialTheme.bt
    val i = sighting.info
    val twoPods = i.modelInfo?.form != com.btekosistem.android.protocol.AppleForm.HEADSET
    val charging = if (twoPods) i.leftCharging || i.rightCharging || i.caseCharging else i.headsetCharging
    BtCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            Text(
                i.modelName ?: stringResource(R.string.apple_unknown_model), Modifier.weight(1f),
                style = BtType.cardTitle, color = c.text, maxLines = 2,
            )
            if (charging) Icon(BtIcons.Bolt, stringResource(R.string.battery_charging), Modifier.size(20.dp), tint = c.up)
        }
        Text(stringResource(R.string.apple_title), style = BtType.caption, color = c.textSecondary)
        Row(Modifier.fillMaxWidth().padding(top = Space.sm), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.Top) {
            if (twoPods) {
                BatteryBadge(stringResource(R.string.battery_left_short), stringResource(R.string.battery_left), i.left, i.leftCharging, Modifier.weight(1f))
                if (i.modelInfo?.hasCase != false) {
                    BatteryBadge(stringResource(R.string.battery_case_short), stringResource(R.string.battery_case), i.caseBattery, i.caseCharging, Modifier.weight(1f))
                }
                BatteryBadge(stringResource(R.string.battery_right_short), stringResource(R.string.battery_right), i.right, i.rightCharging, Modifier.weight(1f))
            } else {
                BatteryBadge(stringResource(R.string.battery_headset).take(1), stringResource(R.string.battery_headset), i.headsetBattery, i.headsetCharging, Modifier.weight(1f))
            }
        }
        val states = buildList {
            if (twoPods && (i.leftInEar || i.rightInEar)) add(stringResource(R.string.apple_in_ear))
            if (twoPods && i.bothPodsInCase) add(stringResource(R.string.apple_in_case))
            if (twoPods && i.lidOpen && i.onePodInCase) add(stringResource(R.string.apple_lid_open))
        }
        if (states.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) { states.forEach { Chip(it, c.textSecondary, c.fill) } }
        }
        Text(stringResource(R.string.apple_readonly), style = BtType.caption, color = c.textTertiary)
    }
}
