package com.btekosistem.android.ui

import android.provider.Settings
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.ui.res.stringResource
import com.btekosistem.android.R
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.btekosistem.android.ui.theme.BtShape
import com.btekosistem.android.ui.theme.BtType
import com.btekosistem.android.ui.theme.Space
import com.btekosistem.android.ui.theme.bt

/** Sistemde animasyonlar kapaliysa (Reduce Motion / animator scale 0) true. */
@Composable
fun rememberReduceMotion(): Boolean {
    val ctx = LocalContext.current
    return remember {
        runCatching { Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
            .getOrDefault(false)
    }
}

/** 150-250 ms araligi; hareket azaltma aciksa anlik. */
fun <T> motion(reduce: Boolean, ms: Int = 200): FiniteAnimationSpec<T> = if (reduce) snap() else tween(ms)

fun <T> softSpring(reduce: Boolean): FiniteAnimationSpec<T> =
    if (reduce) snap() else spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessMediumLow)

/** Tum kartlar: kose 28, ic bosluk 20, ic oge araligi 12; kenarlik yok (sade). */
@Composable
fun BtCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(BtShape.lg),
        color = MaterialTheme.bt.card,
        shadowElevation = 2.dp,
    ) {
        Column(Modifier.padding(Space.xl), verticalArrangement = Arrangement.spacedBy(Space.md), content = content)
    }
}

@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier, style = BtType.sectionTitle, color = MaterialTheme.bt.textSecondary)
}

@Composable
fun Chip(text: String, fg: Color, bg: Color, modifier: Modifier = Modifier) {
    Text(
        text,
        modifier = modifier.clip(RoundedCornerShape(BtShape.sm)).background(bg).padding(horizontal = 8.dp, vertical = 4.dp),
        style = BtType.caption, color = fg,
    )
}

/** Dolu (ana eylem) ya da cizgili (ikincil) kapsul dugme; en az 48 dp, ripple. */
@Composable
fun BtButton(
    text: String, onClick: () -> Unit, modifier: Modifier = Modifier,
    primary: Boolean = true, enabled: Boolean = true, icon: ImageVector? = null, container: Color? = null,
) {
    val c = MaterialTheme.bt
    val bg = container ?: if (primary) c.navy else Color.Transparent
    val fg = if (primary || container != null) c.onNavy else c.text
    Surface(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.heightIn(min = 48.dp),
        shape = RoundedCornerShape(50),
        color = if (enabled) bg else c.fill,
        contentColor = if (enabled) fg else c.textTertiary,
        border = if (primary || container != null) null else BorderStroke(1.dp, c.separator),
    ) {
        Row(
            Modifier.padding(horizontal = Space.xl, vertical = Space.sm),
            horizontalArrangement = Arrangement.spacedBy(Space.sm, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (icon != null) Icon(icon, null, Modifier.size(20.dp))
            Text(text, style = BtType.rowTitle, textAlign = TextAlign.Center)
        }
    }
}

@Composable
fun StatusDot(color: Color, size: Dp = 8.dp) {
    Box(Modifier.size(size).clip(CircleShape).background(color))
}

/** Yuvarlak eylem dugmesi + altinda etiket (Cevapla, Reddet, Kapat). */
@Composable
fun RoundButton(icon: ImageVector, label: String, container: Color, tint: Color, onClick: () -> Unit, modifier: Modifier = Modifier, size: Dp = 72.dp) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.sm)) {
        Box(
            Modifier.size(size).clip(CircleShape).background(container).clickable(role = Role.Button, onClick = onClick),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, label, Modifier.size(size / 2.4f), tint = tint) }
        Text(label, style = BtType.caption, color = MaterialTheme.bt.text)
    }
}

/** Acik/kapali yuvarlak dugme (Kulak algilama, Otomatik gecis, Sessiz). */
@Composable
fun ToggleTile(icon: ImageVector, label: String, on: Boolean, enabled: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val c = MaterialTheme.bt
    val reduce = rememberReduceMotion()
    val bg by animateColorAsState(if (on) c.navy else c.fill, motion(reduce, 200), label = "toggleBg")
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.sm)) {
        Box(
            Modifier.size(64.dp).clip(CircleShape).background(bg)
                .clickable(enabled = enabled, role = Role.Switch, onClick = onClick)
                .semantics { contentDescription = label },
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, null, Modifier.size(28.dp), tint = if (on) c.onNavy else if (enabled) c.text else c.textTertiary)
        }
        Text(label, style = BtType.caption, color = if (enabled) c.text else c.textTertiary, textAlign = TextAlign.Center)
    }
}

/** Bos durum: sade ikon + tek cumle + net eylem. */
@Composable
fun EmptyState(icon: ImageVector, title: String, body: String, modifier: Modifier = Modifier, action: String? = null, onAction: () -> Unit = {}) {
    val c = MaterialTheme.bt
    Column(
        modifier.fillMaxWidth().padding(vertical = Space.sm),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Space.md),
    ) {
        Box(Modifier.size(64.dp).clip(CircleShape).background(c.navySoft), contentAlignment = Alignment.Center) {
            Icon(icon, null, Modifier.size(30.dp), tint = c.accentText)
        }
        Text(title, style = BtType.rowTitle, color = c.text, textAlign = TextAlign.Center)
        Text(body, style = BtType.body, color = c.textSecondary, textAlign = TextAlign.Center)
        if (action != null) BtButton(action, onAction, Modifier.sizeIn(minWidth = 160.dp))
    }
}

/** Referanstaki "ON (tik)" hap anahtar: gri hap, siyah yuvarlak topuz; acikken tik, metin karsi tarafta. */
@Composable
fun BtPillSwitch(checked: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val c = MaterialTheme.bt
    val reduce = rememberReduceMotion()
    val knobX by animateDpAsState(if (checked) 34.dp else 2.dp, motion(reduce, 200), label = "knob")
    Box(
        modifier.sizeIn(minWidth = 72.dp, minHeight = 48.dp)
            .toggleable(checked, enabled, Role.Switch, onChange),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(width = 64.dp, height = 32.dp).clip(CircleShape).background(c.fill)) {
            Text(
                stringResource(if (checked) R.string.switch_on else R.string.switch_off),
                Modifier.align(if (checked) Alignment.CenterStart else Alignment.CenterEnd).padding(horizontal = 10.dp),
                style = BtType.micro.copy(letterSpacing = androidx.compose.ui.unit.TextUnit.Unspecified),
                color = if (enabled) c.textSecondary else c.textTertiary,
            )
            Box(
                Modifier.padding(start = knobX, top = 2.dp).size(28.dp).clip(CircleShape)
                    .background(if (checked && enabled) c.navy else if (checked) c.textTertiary else c.separator),
                contentAlignment = Alignment.Center,
            ) { if (checked) Icon(Icons.Rounded.Check, null, Modifier.size(16.dp), tint = c.onNavy) }
        }
    }
}
