package com.btekosistem.android.ui.theme

import android.app.Activity
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Sade monokrom palet: siyah / beyaz / gri + tek vurgu (accent). "navy" adi geriye uyum icin kaldi:
 * ana dolgu rengi (acikta siyah, koyuda beyaz). Pil anlamlari: up = sarj/iyi, down = dusuk pil.
 */
class BtColors(
    val bg: Color, val card: Color, val fill: Color, val separator: Color,
    val text: Color, val textSecondary: Color, val textTertiary: Color,
    val navy: Color, val accent: Color, val navySoft: Color, val onNavy: Color, val accentText: Color,
    val up: Color, val upBg: Color, val down: Color, val downBg: Color,
    val dark: Boolean,
)

private val LightPalette = BtColors(
    bg = Color(0xFFECEFF4), card = Color(0xFFFFFFFF), fill = Color(0xFFF1F3F7), separator = Color(0xFFE3E7EE),
    text = Color(0xFF0E0F12), textSecondary = Color(0xFF5F6672), textTertiary = Color(0xFF666C78),
    navy = Color(0xFF0E0F12), accent = Color(0xFF0E0F12), navySoft = Color(0xFFF1F3F7), onNavy = Color(0xFFFFFFFF), accentText = Color(0xFF0E0F12),
    up = Color(0xFF1E8E3E), upBg = Color(0xFFE6F4EA), down = Color(0xFFD70015), downBg = Color(0xFFFDECEE),
    dark = false,
)

val LocalBtColors = staticCompositionLocalOf { LightPalette }

/** Kose yaricaplari: sm 8, md 12, lg 28 (buyuk kartlar), xl 28. */
object BtShape {
    val sm = 8.dp
    val md = 12.dp
    val lg = 28.dp
    val xl = 28.dp
}

/** Bosluk ritmi: 4 tabanli. */
object Space {
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 16.dp
    val xl = 20.dp
    val xxl = 24.dp
}

object BtType {
    val pageTitle = TextStyle(fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.3).sp)
    val sectionTitle = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium)
    val cardTitle = TextStyle(fontSize = 20.sp, lineHeight = 26.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp)
    val rowTitle = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold)
    val body = TextStyle(fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Normal)
    val caption = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium)
    val micro = TextStyle(fontSize = 10.sp, lineHeight = 12.sp, fontWeight = FontWeight.Medium, letterSpacing = 1.sp)
    val numLarge = TextStyle(fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.SemiBold)
    val keypad = TextStyle(fontSize = 28.sp, lineHeight = 32.sp, fontWeight = FontWeight.Normal)
}

val MaterialTheme.bt: BtColors
    @Composable get() = LocalBtColors.current

/** Uygulama HER ZAMAN acik temadir; sistem koyu olsa bile degismez. */
@Composable
fun BtTheme(content: @Composable () -> Unit) {
    val p = LightPalette
    val scheme = lightColorScheme(
        primary = p.navy, onPrimary = p.onNavy, background = p.bg, onBackground = p.text,
        surface = p.card, onSurface = p.text, surfaceVariant = p.fill, onSurfaceVariant = p.textSecondary,
        outline = p.separator, error = p.down,
    )
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as? Activity)?.window ?: return@SideEffect
            val ctl = WindowCompat.getInsetsController(window, view)
            ctl.isAppearanceLightStatusBars = true
            ctl.isAppearanceLightNavigationBars = true
        }
    }
    CompositionLocalProvider(LocalBtColors provides p) {
        MaterialTheme(
            colorScheme = scheme,
            typography = Typography(),
            shapes = Shapes(
                small = androidx.compose.foundation.shape.RoundedCornerShape(BtShape.sm),
                medium = androidx.compose.foundation.shape.RoundedCornerShape(BtShape.md),
                large = androidx.compose.foundation.shape.RoundedCornerShape(BtShape.lg),
            ),
            content = content,
        )
    }
}
