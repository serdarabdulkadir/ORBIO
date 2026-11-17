package com.btekosistem.android.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.btekosistem.android.R
import com.btekosistem.android.ui.theme.BtType
import com.btekosistem.android.ui.theme.Space
import com.btekosistem.android.ui.theme.bt

const val LOW_BATTERY = 20

/** Halka gosterge: deger ortada, altinda etiket ve (sarj / dusuk pil <= %20) rozeti. Deger yoksa bos halka. */
@Composable
fun BatteryRing(label: String, level: Int?, charging: Boolean, modifier: Modifier = Modifier) {
    val c = MaterialTheme.bt
    val reduce = rememberReduceMotion()
    val low = level != null && level <= LOW_BATTERY
    val accent = when {
        low -> c.down
        charging -> c.up
        level == null -> c.textTertiary
        else -> c.accent
    }
    val sweep by animateFloatAsState((level ?: 0) / 100f, motion(reduce, 250), label = "ring")
    val track = c.separator
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.sm)) {
        Box(Modifier.size(104.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val stroke = 10.dp.toPx()
                val sz = Size(size.width - stroke, size.height - stroke)
                val tl = Offset(stroke / 2, stroke / 2)
                drawArc(track, -90f, 360f, false, tl, sz, style = Stroke(stroke))
                if (level != null) drawArc(accent, -90f, 360f * sweep, false, tl, sz, style = Stroke(stroke, cap = StrokeCap.Round))
            }
            Text(
                if (level != null) "%$level" else stringResource(R.string.battery_none),
                style = BtType.numLarge, color = if (level != null) c.text else c.textTertiary, maxLines = 1,
            )
        }
        Text(label, style = BtType.caption, color = c.textSecondary)
        when {
            charging -> Chip(stringResource(R.string.battery_charging), c.up, c.upBg)
            low -> Chip(stringResource(R.string.battery_low), c.down, c.downBg)
        }
    }
}
