package com.btekosistem.android.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.btekosistem.android.R
import com.btekosistem.android.peer.LocalMedia
import com.btekosistem.android.peer.MediaCmd
import com.btekosistem.android.peer.MediaTarget
import com.btekosistem.android.protocol.ListeningMode
import com.btekosistem.android.protocol.QcyCustomEq
import com.btekosistem.android.protocol.QcyEqPreset
import com.btekosistem.android.ui.theme.BtShape
import com.btekosistem.android.ui.theme.BtType
import com.btekosistem.android.ui.theme.Space
import com.btekosistem.android.ui.theme.bt
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.offset
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.math.roundToInt

// ---------------------------------------------------------------- Hero: iki kulaklik (vektor)

private val BudHi = Color(0xFF5B616C)
private val BudMid = Color(0xFF262A31)
private val BudLow = Color(0xFF0C0D10)

/**
 * Canvas ile cizilen iki TWS kulaklik (parlak siyah govde, silikon uc, mikrofon deligi, LED).
 * Sag kulaklik onde ve biraz buyuk; ikisi hafif egik. Bagliyken nefes alan hale + LED, degilken soluk.
 * Hero yuksekligi 150 dp; kartin ustune 78 dp'den baslar (HeroCard).
 */
@Composable
fun EarbudsHero(connected: Boolean = true, modifier: Modifier = Modifier) {
    val c = MaterialTheme.bt
    val reduce = rememberReduceMotion()
    val desc = stringResource(R.string.hero_a11y)
    val t = if (reduce) 0.5f else {
        val tr = rememberInfiniteTransition(label = "hero")
        val v by tr.animateFloat(0f, 1f, infiniteRepeatable(tween(if (connected) 2600 else 4200, easing = FastOutSlowInEasing), RepeatMode.Reverse), label = "breath")
        v
    }
    val halo = if (connected) c.up else c.navy
    val up = c.up
    Canvas(
        modifier.fillMaxWidth().height(150.dp).semantics { contentDescription = desc }
            .graphicsLayer { alpha = if (connected) 1f else 0.55f + 0.15f * t },
    ) {
        val cx = size.width / 2
        val cy = 64.dp.toPx() + (if (connected) (t - 0.5f) * 3.dp.toPx() else 0f)
        // yumusak hale
        val haloA = if (connected) 0.10f + 0.10f * t else 0.06f
        drawCircle(
            Brush.radialGradient(listOf(halo.copy(alpha = haloA), Color.Transparent), Offset(cx, cy), 125.dp.toPx()),
            125.dp.toPx(), Offset(cx, cy),
        )
        val u = 0.95.dp.toPx()
        val dx = 46.dp.toPx()
        drawBud(Offset(cx - dx, cy - 3.dp.toPx()), u * 0.88f, -1f, -14f, false, up, t)
        drawBud(Offset(cx + dx, cy + 3.dp.toPx()), u, 1f, 14f, connected, up, t)
    }
}

/** side = +1 sag kulaklik (uc sagda), -1 sol (uc solda). Birim: 1 = u piksel; govde 72x80 birim. */
private fun DrawScope.drawBud(center: Offset, u: Float, side: Float, tilt: Float, led: Boolean, ledColor: Color, t: Float) {
    // zemin golgesi (egimsiz, kartin uzerine duser)
    withTransform({ translate(center.x, center.y + 40 * u); scale(1f, 0.16f, Offset.Zero) }) {
        drawCircle(Brush.radialGradient(listOf(Color.Black.copy(alpha = 0.30f), Color.Transparent), Offset.Zero, 52 * u), 52 * u, Offset.Zero)
    }
    withTransform({ translate(center.x, center.y); rotate(tilt, Offset.Zero); scale(side * u, u, Offset.Zero) }) {
        // silikon uc: sap + kubbe + ic delik
        drawRoundRect(
            Brush.verticalGradient(listOf(Color(0xFF2A2D33), Color(0xFF0B0C0E)), -8f, 9f),
            Offset(26f, -8f), Size(24f, 17f), CornerRadius(8.5f),
        )
        drawOval(
            Brush.radialGradient(listOf(Color(0xFF50555E), Color(0xFF1C1F24), Color(0xFF08090B)), Offset(52f, -7f), 26f),
            Offset(44f, -17f), Size(25f, 38f),
        )
        drawOval(Brush.radialGradient(listOf(Color.Black, Color(0xFF1A1C20)), Offset(63f, 2f), 9f), Offset(59f, -7f), Size(8f, 18f))
        drawOval(Color.White.copy(alpha = 0.14f), Offset(59f, -7f), Size(8f, 18f), style = Stroke(0.8f))
        // ana govde
        drawOval(
            Brush.radialGradient(listOf(BudHi, BudMid, BudLow), Offset(-12f, -16f), 64f),
            Offset(-36f, -40f), Size(72f, 80f),
        )
        drawOval(
            Brush.linearGradient(listOf(Color.White.copy(alpha = 0.6f), Color.Transparent, Color.White.copy(alpha = 0.18f)), Offset(-30f, -40f), Offset(30f, 40f)),
            Offset(-36f, -40f), Size(72f, 80f), style = Stroke(1.6f),
        )
        // dokunmatik yuz
        drawOval(
            Brush.linearGradient(listOf(Color(0xFF3A3E46), Color(0xFF0A0B0D)), Offset(-24f, -30f), Offset(26f, 32f)),
            Offset(-27f, -31f), Size(54f, 62f),
        )
        drawOval(Color.Black.copy(alpha = 0.5f), Offset(-27f, -31f), Size(54f, 62f), style = Stroke(1f))
        // parlama (specular)
        withTransform({ rotate(-35f, Offset(-8f, -24f)) }) {
            drawOval(
                Brush.radialGradient(listOf(Color.White.copy(alpha = 0.7f), Color.Transparent), Offset(-8f, -24f), 15f),
                Offset(-22f, -30f), Size(28f, 12f),
            )
        }
        drawArc(
            Brush.linearGradient(listOf(Color.White.copy(alpha = 0.5f), Color.Transparent), Offset(-24f, -26f), Offset(0f, 0f)),
            195f, 60f, false, Offset(-22f, -26f), Size(44f, 52f), style = Stroke(2.2f, cap = StrokeCap.Round),
        )
        drawArc(Color.White.copy(alpha = 0.10f), 30f, 55f, false, Offset(-22f, -26f), Size(44f, 52f), style = Stroke(3f, cap = StrokeCap.Round))
        // logo halkasi
        drawCircle(Color.White.copy(alpha = 0.55f), 5.5f, Offset(0f, 2f), style = Stroke(1.3f))
        drawCircle(Color.White.copy(alpha = 0.55f), 1.4f, Offset(0f, 2f))
        // mikrofon deligi + ikinci delik
        drawCircle(Color.Black, 2.2f, Offset(-6f, 31f))
        drawCircle(Color.White.copy(alpha = 0.28f), 2.8f, Offset(-6f, 31f), style = Stroke(0.7f))
        drawCircle(Color.Black, 1.6f, Offset(6f, 31f))
        drawCircle(Color.White.copy(alpha = 0.2f), 2.1f, Offset(6f, 31f), style = Stroke(0.6f))
        // LED
        if (led) {
            drawCircle(ledColor.copy(alpha = 0.25f + 0.25f * t), 6f, Offset(22f, -16f))
            drawCircle(ledColor, 1.9f, Offset(22f, -16f))
        }
    }
}

// ---------------------------------------------------------------- Pil gostergeleri

/** L / Kutu / R: yuvarlak harf rozeti, yuzde ve ince cubuk. Deger yoksa "Yok". */
@Composable
fun BatteryBadge(letter: String, label: String, level: Int?, charging: Boolean, modifier: Modifier = Modifier) {
    val c = MaterialTheme.bt
    val low = level != null && level <= LOW_BATTERY
    val bar = when {
        low -> c.down
        charging -> c.up
        else -> c.text
    }
    val a11y = if (level != null) stringResource(R.string.battery_a11y, label, level) else stringResource(R.string.battery_a11y_none, label)
    Column(
        modifier.semantics(mergeDescendants = true) { contentDescription = a11y },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.width(56.dp).height(4.dp).clip(CircleShape).background(c.separator)) {
            if (level != null) Box(Modifier.fillMaxHeight().fillMaxWidth(level.coerceIn(0, 100) / 100f).background(bar))
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            Box(Modifier.size(22.dp).clip(CircleShape).background(c.fill), contentAlignment = Alignment.Center) {
                Text(letter, style = microFlat, color = c.text)
            }
            Text(
                if (level != null) "%$level" else stringResource(R.string.battery_none),
                style = BtType.rowTitle, color = if (level != null) c.text else c.textTertiary, maxLines = 1,
            )
        }
        when {
            charging -> Text(stringResource(R.string.battery_charging), style = BtType.caption, color = c.up)
            low -> Text(stringResource(R.string.battery_low), style = BtType.caption, color = c.down)
        }
    }
}

private val microFlat get() = BtType.micro.copy(letterSpacing = androidx.compose.ui.unit.TextUnit.Unspecified)

// ---------------------------------------------------------------- Gurultu kontrolu: 3 dilimli kadran

private val DIAL_SIZE = 236.dp
private val DIAL_RING = 44.dp

private fun dialCenter(m: ListeningMode): Float = when (m) {
    ListeningMode.GURULTU_ENGELLEME -> 150f
    ListeningMode.KAPALI -> 270f
    else -> 30f
}

private fun dialIcon(m: ListeningMode) = when (m) {
    ListeningMode.GURULTU_ENGELLEME -> BtIcons.NoiseCancel
    ListeningMode.KAPALI -> BtIcons.ModeOff
    else -> BtIcons.Hearing
}

private fun dialLabel(m: ListeningMode) = when (m) {
    ListeningMode.GURULTU_ENGELLEME -> R.string.mode_anc
    ListeningMode.KAPALI -> R.string.mode_off
    else -> R.string.mode_transparent
}

private val DIAL_MODES = listOf(ListeningMode.GURULTU_ENGELLEME, ListeningMode.KAPALI, ListeningMode.SEFFAF)

/**
 * Beats tarzi daire: 3 dilim (Gurultu engelleme / Kapali / Seffaf), secili dilim siyah; ortada ses yuzdesi ve -/+.
 * Altinda secili modun adi. volume < 0 ise ortadaki ses bolumu gizlenir.
 */
@Composable
fun NoiseDial(
    selected: ListeningMode?, enabled: Boolean, onSelect: (ListeningMode) -> Unit,
    volumePercent: Int, volumeEnabled: Boolean, onVolumeDelta: (Int) -> Unit, modifier: Modifier = Modifier,
) {
    val c = MaterialTheme.bt
    val reduce = rememberReduceMotion()
    val a11y = stringResource(R.string.noise_dial_a11y)
    val density = LocalDensity.current
    val iconR = (DIAL_SIZE / 2 - DIAL_RING / 2)
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.sm)) {
        Box(Modifier.size(DIAL_SIZE).semantics { contentDescription = a11y }, contentAlignment = Alignment.Center) {
            val fills = DIAL_MODES.map { m ->
                val on = m == selected
                animateColorAsState(if (on) c.navy else c.fill, motion(reduce, 200), label = "slice")
            }
            Canvas(
                Modifier.matchParentSize().pointerInput(enabled) {
                    if (!enabled) return@pointerInput
                    detectTapGestures { o ->
                        val r = size.width / 2f
                        val dx = o.x - r
                        val dy = o.y - r
                        val d = hypot(dx, dy)
                        if (d > r || d < r - DIAL_RING.toPx()) return@detectTapGestures
                        val ang = ((Math.toDegrees(atan2(dy, dx).toDouble()) + 360.0) % 360.0).toFloat()
                        val hit = DIAL_MODES.minByOrNull { m ->
                            val diff = abs(ang - dialCenter(m)) % 360f
                            if (diff > 180f) 360f - diff else diff
                        }
                        if (hit != null) onSelect(hit)
                    }
                },
            ) {
                val w = DIAL_RING.toPx()
                val gap = 5f
                DIAL_MODES.forEachIndexed { i, m ->
                    drawArc(
                        fills[i].value, dialCenter(m) - 60f + gap / 2, 120f - gap, false,
                        Offset(w / 2, w / 2), Size(size.width - w, size.height - w), style = Stroke(w),
                    )
                }
            }
            DIAL_MODES.forEach { m ->
                val on = m == selected
                val rad = Math.toRadians(dialCenter(m).toDouble())
                val ox = with(density) { (cos(rad) * iconR.toPx()).toFloat().toDp() }
                val oy = with(density) { (sin(rad) * iconR.toPx()).toFloat().toDp() }
                val label = stringResource(dialLabel(m))
                Box(
                    Modifier.offset(ox, oy).size(48.dp).clip(CircleShape)
                        .clickable(enabled = enabled, role = Role.RadioButton) { onSelect(m) }
                        .semantics { this.selected = on; contentDescription = label },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(dialIcon(m), null, Modifier.size(24.dp), tint = if (on) c.onNavy else if (enabled) c.text else c.textTertiary)
                }
            }
            // orta: ses
            Column(
                Modifier.size((DIAL_SIZE - DIAL_RING * 2 - 16.dp)).shadow(4.dp, CircleShape).clip(CircleShape).background(c.card),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
            ) {
                Text(stringResource(R.string.vol_title), style = BtType.caption, color = c.textSecondary)
                Text("%$volumePercent", style = BtType.cardTitle.copy(fontSize = 28.sp, lineHeight = 32.sp), color = if (volumeEnabled) c.text else c.textTertiary)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(top = 2.dp)) {
                    VolButton(BtIcons.Remove,stringResource(R.string.vol_down), volumeEnabled) { onVolumeDelta(-1) }
                    VolButton(Icons.Rounded.Add, stringResource(R.string.vol_up), volumeEnabled) { onVolumeDelta(1) }
                }
            }
        }
        Text(
            selected?.let { stringResource(dialLabel(it)) } ?: "",
            style = BtType.rowTitle, color = c.text, textAlign = TextAlign.Center, modifier = Modifier.heightIn(min = 20.dp),
        )
    }
}

@Composable
private fun VolButton(icon: ImageVector, label: String, enabled: Boolean, onClick: () -> Unit) {
    val c = MaterialTheme.bt
    Box(
        Modifier.size(48.dp).clip(CircleShape).background(c.fill)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, Modifier.size(20.dp), tint = if (enabled) c.text else c.textTertiary) }
}

// ---------------------------------------------------------------- Hap kaydirici ("01 --- 05")

/** Referanstaki hap kaydirici: siyah dolgu, beyaz topuz (deger ortada), uclarda min ve max (seffaflikta 01 ve 05). */
@Composable
fun PillSlider(value: Int, min: Int, max: Int, enabled: Boolean, onChange: (Int) -> Unit, modifier: Modifier = Modifier) {
    val c = MaterialTheme.bt
    val change by rememberUpdatedState(onChange)
    val cur by rememberUpdatedState(value)
    val thumbW = 68.dp
    fun f(v: Int) = "%02d".format(v)
    BoxWithConstraints(
        modifier.fillMaxWidth().height(56.dp).clip(CircleShape).background(c.fill)
            .semantics {
                progressBarRangeInfo = ProgressBarRangeInfo(value.toFloat(), min.toFloat()..max.toFloat(), max - min - 1)
                setProgress { v -> if (enabled) { change(v.roundToInt().coerceIn(min, max)); true } else false }
            },
    ) {
        val trackPx = with(LocalDensity.current) { (maxWidth - thumbW).toPx() }
        val frac = ((value - min).toFloat() / (max - min)).coerceIn(0f, 1f)
        val thumbX = maxWidth.times(0f) + (maxWidth - thumbW) * frac
        Box(Modifier.fillMaxHeight().width(thumbX + thumbW / 2).clip(CircleShape).background(if (enabled) c.navy else c.textTertiary))
        Text(f(min), Modifier.align(Alignment.CenterStart).padding(start = 20.dp), style = BtType.rowTitle, color = c.onNavy)
        Text(f(max), Modifier.align(Alignment.CenterEnd).padding(end = 20.dp), style = BtType.rowTitle, color = c.textSecondary)
        Box(
            Modifier.offset(thumbX).padding(3.dp).size(thumbW - 6.dp, 50.dp).clip(CircleShape).background(c.card),
            contentAlignment = Alignment.Center,
        ) { Text(f(value), style = BtType.rowTitle, color = c.text) }
        Box(
            Modifier.matchParentSize().pointerInput(enabled, min, max, trackPx) {
                if (!enabled) return@pointerInput
                fun at(x: Float): Int {
                    val fr = ((x - thumbW.toPx() / 2) / trackPx).coerceIn(0f, 1f)
                    return (min + fr * (max - min)).roundToInt()
                }
                detectTapGestures { o -> val v = at(o.x); if (v != cur) change(v) }
            }.pointerInput(enabled, min, max, trackPx) {
                if (!enabled) return@pointerInput
                detectDragGestures { pt, _ ->
                    val fr = ((pt.position.x - thumbW.toPx() / 2) / trackPx).coerceIn(0f, 1f)
                    val v = (min + fr * (max - min)).roundToInt()
                    if (v != cur) change(v)
                    pt.consume()
                }
            },
        )
    }
}

// ---------------------------------------------------------------- Ekolayzer: hazir ayar cipleri

private fun presetBars(p: QcyEqPreset): List<Float> = when (p) {
    QcyEqPreset.DEFAULT -> listOf(.55f, .55f, .55f, .55f, .55f)
    QcyEqPreset.POP -> listOf(.4f, .6f, .85f, .6f, .45f)
    QcyEqPreset.BASS -> listOf(.95f, .75f, .5f, .4f, .35f)
    QcyEqPreset.ROCK -> listOf(.8f, .5f, .4f, .55f, .85f)
    QcyEqPreset.SOFT -> listOf(.35f, .45f, .5f, .4f, .3f)
    QcyEqPreset.CLASSIC -> listOf(.5f, .6f, .45f, .7f, .8f)
}

/** Ikonlu ayar cipi: ikon, ayarin bant sekline gore cizilmis 5 cubuk (vektor). */
@Composable
fun PresetChip(label: String, preset: QcyEqPreset, selected: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val c = MaterialTheme.bt
    val fg = if (selected) c.onNavy else if (enabled) c.text else c.textTertiary
    val bars = presetBars(preset)
    Column(
        Modifier.width(88.dp).heightIn(min = 96.dp).clip(RoundedCornerShape(22.dp))
            .background(if (selected) c.navy else c.fill)
            .clickable(enabled = enabled, role = Role.RadioButton, onClick = onClick)
            .semantics { this.selected = selected }
            .padding(vertical = Space.md),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.sm, Alignment.CenterVertically),
    ) {
        Box(Modifier.size(38.dp).border(1.dp, fg.copy(alpha = 0.35f), CircleShape), contentAlignment = Alignment.Center) {
            Canvas(Modifier.size(18.dp)) {
                val w = size.width / 9f
                bars.forEachIndexed { i, h ->
                    val bh = size.height * h
                    drawRoundRect(fg, Offset(w * (i * 2), size.height - bh), Size(w, bh), CornerRadius(w / 2))
                }
            }
        }
        Text(label, style = BtType.caption, color = fg, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

// ---------------------------------------------------------------- Ekolayzer: 10 bantli noktali grafik

private const val EQ_RANGE = 8
private val EQ_INSET = 14.dp

private fun freqLabel(hz: Int) = when {
    hz < 1000 -> "$hz"
    hz % 1000 == 0 -> "${hz / 1000}K"
    else -> "${(hz / 100) / 10.0}K"
}

/** Surukle: nokta ±8 dB. Dokunma da en yakin bandi o yukseklige tasir. TalkBack icin her bant ayarlanabilir dugumdur. */
@Composable
fun EqChart(gains: List<Int>, enabled: Boolean, onChange: (List<Int>) -> Unit, modifier: Modifier = Modifier) {
    val c = MaterialTheme.bt
    val n = QcyCustomEq.BAND_COUNT
    val cur by rememberUpdatedState(gains)
    val change by rememberUpdatedState(onChange)
    var active by remember { mutableIntStateOf(-1) }
    val grid = c.separator
    val dot = c.navy
    val dotRing = c.card
    val chartH = 200.dp

    fun set(i: Int, v: Int) {
        val g = v.coerceIn(-EQ_RANGE, EQ_RANGE)
        if (cur[i] != g) change(cur.toMutableList().also { it[i] = g })
    }

    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
        Row(Modifier.fillMaxWidth()) {
            Column(Modifier.width(32.dp).height(chartH).padding(vertical = EQ_INSET - 7.dp), verticalArrangement = Arrangement.SpaceBetween) {
                listOf(EQ_RANGE, EQ_RANGE / 2, 0, -EQ_RANGE / 2, -EQ_RANGE).forEach {
                    Text("$it", style = microFlat, color = c.textSecondary, maxLines = 1)
                }
            }
            Box(Modifier.weight(1f).height(chartH)) {
                Canvas(
                    Modifier.matchParentSize()
                        .pointerInput(enabled) {
                            if (!enabled) return@pointerInput
                            val inset = EQ_INSET.toPx()
                            fun gainAt(y: Float) = (EQ_RANGE - (y - inset) / (size.height - 2 * inset) * 2 * EQ_RANGE).roundToInt()
                            fun bandAt(x: Float) = (x / size.width * n).toInt().coerceIn(0, n - 1)
                            detectTapGestures { o -> set(bandAt(o.x), gainAt(o.y)) }
                        }
                        .pointerInput(enabled) {
                            if (!enabled) return@pointerInput
                            val inset = EQ_INSET.toPx()
                            fun gainAt(y: Float) = (EQ_RANGE - (y - inset) / (size.height - 2 * inset) * 2 * EQ_RANGE).roundToInt()
                            fun bandAt(x: Float) = (x / size.width * n).toInt().coerceIn(0, n - 1)
                            detectDragGestures(
                                onDragStart = { o -> active = bandAt(o.x); set(active, gainAt(o.y)) },
                                onDragEnd = { active = -1 }, onDragCancel = { active = -1 },
                            ) { pt, _ -> if (active >= 0) set(active, gainAt(pt.position.y)); pt.consume() }
                        },
                ) {
                    val inset = EQ_INSET.toPx()
                    val h = size.height - 2 * inset
                    val dash = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 6.dp.toPx()))
                    for (k in 0..4) {
                        val y = inset + h * k / 4f
                        drawLine(grid, Offset(0f, y), Offset(size.width, y), strokeWidth = if (k == 2) 1.5.dp.toPx() else 1.dp.toPx(), pathEffect = dash)
                    }
                    fun x(i: Int) = size.width * (i + 0.5f) / n
                    fun y(g: Int) = inset + h * (EQ_RANGE - g) / (2f * EQ_RANGE)
                    for (i in 0 until n) drawLine(grid, Offset(x(i), inset), Offset(x(i), inset + h), strokeWidth = 1.dp.toPx(), pathEffect = dash)
                    gains.forEachIndexed { i, g ->
                        val r = if (i == active) 11.dp.toPx() else 8.dp.toPx()
                        drawCircle(dotRing, r + 2.dp.toPx(), Offset(x(i), y(g)))
                        drawCircle(if (enabled) dot else c.textTertiary, r, Offset(x(i), y(g)))
                    }
                }
                Row(Modifier.matchParentSize()) {
                    QcyCustomEq.FREQUENCIES.forEachIndexed { i, hz ->
                        val name = if (hz >= 1000) "${hz / 1000} kHz" else "$hz Hz"
                        val a11y = stringResource(R.string.eq_band_a11y, name, gains[i])
                        Box(
                            Modifier.weight(1f).fillMaxHeight().semantics {
                                contentDescription = a11y
                                progressBarRangeInfo = ProgressBarRangeInfo(gains[i].toFloat(), -EQ_RANGE.toFloat()..EQ_RANGE.toFloat(), 2 * EQ_RANGE - 1)
                                setProgress { v -> if (enabled) { set(i, v.roundToInt()); true } else false }
                            },
                        )
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(start = 32.dp)) {
            QcyCustomEq.FREQUENCIES.forEach { hz ->
                Text(
                    freqLabel(hz), Modifier.weight(1f), style = microFlat,
                    color = c.textSecondary, textAlign = TextAlign.Center, maxLines = 1,
                )
            }
        }
    }
}

// ---------------------------------------------------------------- Satir: baslik + aciklama + ok

@Composable
fun ArrowRow(title: String, subtitle: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val c = MaterialTheme.bt
    Row(
        modifier.fillMaxWidth().heightIn(min = 56.dp).clip(RoundedCornerShape(BtShape.md))
            .clickable(role = Role.Button, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = BtType.rowTitle, color = c.text)
            Text(subtitle, style = BtType.caption, color = c.textSecondary)
        }
        Icon(BtIcons.ChevronRight, null, Modifier.size(24.dp), tint = c.textSecondary)
    }
}

/** "Dokunuslar          Sol / Sag >" satiri (PULSE). */
@Composable
fun ValueRow(title: String, value: String, enabled: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val c = MaterialTheme.bt
    Row(
        modifier.fillMaxWidth().heightIn(min = 52.dp).clip(RoundedCornerShape(BtShape.md))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm),
    ) {
        Text(title, Modifier.weight(1f), style = BtType.rowTitle, color = if (enabled) c.text else c.textTertiary)
        Text(value, style = BtType.caption, color = c.textSecondary)
        Icon(BtIcons.ChevronRight, null, Modifier.size(20.dp), tint = c.textSecondary)
    }
}

// ---------------------------------------------------------------- Mini oynatici

@Composable
private fun PlayerButton(icon: ImageVector, label: String, onClick: () -> Unit, outlined: Boolean = false) {
    val c = MaterialTheme.bt
    Box(
        Modifier.size(48.dp).clip(CircleShape)
            .then(if (outlined) Modifier.background(c.navy) else Modifier)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, Modifier.size(24.dp), tint = if (outlined) c.onNavy else c.text) }
}

/**
 * Altta sabit mini oynatici: telefondaki parca (kapak, baslik, oynat/duraklat, sonraki).
 * Mac bagliysa ayri "Mac" segmenti yalniz kumanda verir (Mac sarki bilgisi okunamaz).
 */
@Composable
fun MiniPlayer(
    media: LocalMedia, hasAccess: Boolean, macConnected: Boolean,
    onCommand: (MediaTarget, MediaCmd) -> Unit, onOpenAccess: () -> Unit, modifier: Modifier = Modifier,
) {
    val c = MaterialTheme.bt
    Surface(
        modifier.fillMaxWidth(), shape = RoundedCornerShape(BtShape.lg), color = c.card,
        shadowElevation = 4.dp,
    ) {
        Column(Modifier.padding(horizontal = Space.md, vertical = Space.sm)) {
            if (!hasAccess) {
                val label = stringResource(R.string.media_access)
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(BtShape.md))
                        .clickable(role = Role.Button, onClick = onOpenAccess),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md),
                ) {
                    Icon(BtIcons.MusicNote, null, Modifier.padding(start = Space.sm).size(24.dp), tint = c.textSecondary)
                    Text(label, Modifier.weight(1f), style = BtType.rowTitle, color = c.text)
                    Icon(BtIcons.ChevronRight, null, Modifier.size(24.dp), tint = c.textSecondary)
                }
            } else {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.md)) {
                    Box(Modifier.size(52.dp).clip(RoundedCornerShape(16.dp)).background(c.fill), contentAlignment = Alignment.Center) {
                        val art = media.art
                        val img = remember(art) { art?.asImageBitmap() }
                        if (img != null) Image(img, null, Modifier.matchParentSize(), contentScale = ContentScale.Crop)
                        else Icon(BtIcons.MusicNote, null, Modifier.size(24.dp), tint = c.textSecondary)
                    }
                    Column(Modifier.weight(1f)) {
                        Text(
                            if (media.hasSession) media.title ?: stringResource(R.string.media_unknown_title) else stringResource(R.string.media_none),
                            style = BtType.rowTitle, color = c.text, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                        val sub = media.artist ?: media.app
                        if (media.hasSession && sub != null) Text(sub, style = BtType.caption, color = c.textSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    val enabledAlpha = if (media.hasSession) 1f else 0.4f
                    Row(Modifier.alpha(enabledAlpha), horizontalArrangement = Arrangement.spacedBy(Space.xs), verticalAlignment = Alignment.CenterVertically) {
                        PlayerButton(
                            if (media.playing) BtIcons.Pause else BtIcons.PlayArrow,
                            stringResource(if (media.playing) R.string.media_pause else R.string.media_play),
                            { if (media.hasSession) onCommand(MediaTarget.PHONE, MediaCmd.PLAY_PAUSE) }, outlined = true,
                        )
                        PlayerButton(BtIcons.SkipNext, stringResource(R.string.media_next), { if (media.hasSession) onCommand(MediaTarget.PHONE, MediaCmd.NEXT) })
                    }
                }
            }
            if (macConnected) {
                val mac = stringResource(R.string.media_mac)
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                    Text(
                        mac, Modifier.weight(1f).padding(start = Space.sm), style = BtType.caption, color = c.textSecondary,
                    )
                    PlayerButton(BtIcons.SkipPrevious, stringResource(R.string.media_mac_cd, stringResource(R.string.media_previous)), { onCommand(MediaTarget.MAC, MediaCmd.PREVIOUS) })
                    PlayerButton(BtIcons.PlayArrow, stringResource(R.string.media_mac_cd, stringResource(R.string.media_play_pause)), { onCommand(MediaTarget.MAC, MediaCmd.PLAY_PAUSE) })
                    PlayerButton(BtIcons.SkipNext, stringResource(R.string.media_mac_cd, stringResource(R.string.media_next)), { onCommand(MediaTarget.MAC, MediaCmd.NEXT) })
                }
            }
        }
    }
}
