package com.btekosistem.android.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

/** Material Symbols (dolgulu, 24 dp) yollari; core ikon paketinde olmayanlar. */
object BtIcons {
    private fun icon(name: String, d: String, evenOdd: Boolean = false): ImageVector =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f)
            .addPath(PathParser().parsePathString(d).toNodes(), fill = SolidColor(Color.Black), pathFillType = if (evenOdd) PathFillType.EvenOdd else PathFillType.NonZero)
            .build()

    val Bolt: ImageVector by lazy { icon("bolt", "M11,21h-1l1,-7H7.5c-0.58,0 -0.57,-0.32 -0.38,-0.66 0.19,-0.34 0.05,-0.08 0.07,-0.12C8.48,10.94 10.42,7.54 13,3h1l-1,7h3.5c0.49,0 0.56,0.33 0.47,0.51l-0.07,0.15C12.96,17.55 11,21 11,21z") }
    val Remove: ImageVector by lazy { icon("remove", "M19,13H5v-2h14v2z") }
    val Headphones: ImageVector by lazy {
        icon("headphones", "M12,1c-4.97,0 -9,4.03 -9,9v7c0,1.66 1.34,3 3,3h3v-8H5v-2c0,-3.87 3.13,-7 7,-7s7,3.13 7,7v2h-4v8h3c1.66,0 3,-1.34 3,-3v-7c0,-4.97 -4.03,-9 -9,-9z")
    }
    val Bluetooth: ImageVector by lazy {
        icon("bluetooth", "M17.71,7.71L12,2h-1v7.59L6.41,5 5,6.41 10.59,12 5,17.59 6.41,19 11,14.41V22h1l5.71,-5.71 -4.3,-4.29 4.3,-4.29zM13,5.83l1.88,1.88L13,9.59V5.83zM14.88,16.29L13,18.17v-3.76l1.88,1.88z")
    }
    val Eye: ImageVector by lazy {
        icon("visibility", "M12,4.5C7,4.5 2.73,7.61 1,12c1.73,4.39 6,7.5 11,7.5s9.27,-3.11 11,-7.5c-1.73,-4.39 -6,-7.5 -11,-7.5zM12,17c-2.76,0 -5,-2.24 -5,-5s2.24,-5 5,-5 5,2.24 5,5 -2.24,5 -5,5zM12,9c-1.66,0 -3,1.34 -3,3s1.34,3 3,3 3,-1.34 3,-3 -1.34,-3 -3,-3z")
    }
    val VolumeUp: ImageVector by lazy {
        icon("volume_up", "M3,9v6h4l5,5V4L7,9H3zM16.5,12c0,-1.77 -1.02,-3.29 -2.5,-4.03v8.05c1.48,-0.73 2.5,-2.25 2.5,-4.02zM14,3.23v2.06c2.89,0.86 5,3.54 5,6.71s-2.11,5.85 -5,6.71v2.06c4.01,-0.91 7,-4.49 7,-8.77s-2.99,-7.86 -7,-8.77z")
    }
    val CallEnd: ImageVector by lazy {
        icon("call_end", "M12,9c-1.6,0 -3.15,0.25 -4.6,0.72v3.1c0,0.39 -0.23,0.74 -0.56,0.9 -0.98,0.49 -1.87,1.12 -2.66,1.85 -0.18,0.18 -0.43,0.28 -0.7,0.28 -0.28,0 -0.53,-0.11 -0.71,-0.29L0.29,13.08c-0.18,-0.17 -0.29,-0.42 -0.29,-0.7 0,-0.28 0.11,-0.53 0.29,-0.71C3.34,8.78 7.46,7 12,7s8.66,1.78 11.71,4.67c0.18,0.18 0.29,0.43 0.29,0.71 0,0.28 -0.11,0.53 -0.29,0.71l-2.48,2.48c-0.18,0.18 -0.43,0.29 -0.71,0.29 -0.27,0 -0.52,-0.11 -0.7,-0.28 -0.79,-0.74 -1.69,-1.36 -2.67,-1.85 -0.33,-0.16 -0.56,-0.5 -0.56,-0.9v-3.1C15.15,9.25 13.6,9 12,9z")
    }
    /** Mod kapali: daire + capraz cizgi (Material "block"). */
    val ModeOff: ImageVector by lazy {
        icon("block", "M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM4,12c0,-4.42 3.58,-8 8,-8 1.85,0 3.55,0.63 4.9,1.69L5.69,16.9C4.63,15.55 4,13.85 4,12zM12,20c-1.85,0 -3.55,-0.63 -4.9,-1.69L18.31,7.1C19.37,8.45 20,10.15 20,12c0,4.42 -3.58,8 -8,8z")
    }
    /** Gurultu engelleme: halka icinde dolu nokta (aktif iptal). */
    val NoiseCancel: ImageVector by lazy {
        icon("noise_control_on", "M12,2a10,10 0 1,0 0.001,0zM12,4.5a7.5,7.5 0 1,1 -0.001,0zM12,8.5a3.5,3.5 0 1,0 0.001,0z", evenOdd = true)
    }
    /** Seffaf: kulak (Material "hearing"). */
    val Hearing: ImageVector by lazy {
        icon("hearing", "M17,20c-0.29,0 -0.56,-0.06 -0.76,-0.15 -0.71,-0.37 -1.21,-0.88 -1.71,-2.38 -0.51,-1.56 -1.47,-2.29 -2.39,-3 -0.79,-0.61 -1.61,-1.24 -2.32,-2.53C9.29,10.98 9,9.93 9,9c0,-2.8 2.2,-5 5,-5s5,2.2 5,5h2c0,-3.93 -3.07,-7 -7,-7S7,5.07 7,9c0,1.26 0.38,2.65 1.07,3.9 0.91,1.65 1.98,2.48 2.85,3.15 0.81,0.62 1.39,1.07 1.71,2.05 0.6,1.82 1.37,2.84 2.73,3.55 0.51,0.23 1.07,0.35 1.64,0.35 2.21,0 4,-1.79 4,-4h-2c0,1.1 -0.9,2 -2,2zM7.64,2.64L6.22,1.22C4.23,3.21 3,5.96 3,9s1.23,5.79 3.22,7.78l1.41,-1.41C6.01,13.74 5,11.49 5,9s1.01,-4.74 2.64,-6.36zM11.5,9c0,1.38 1.12,2.5 2.5,2.5s2.5,-1.12 2.5,-2.5 -1.12,-2.5 -2.5,-2.5 -2.5,1.12 -2.5,2.5z")
    }
    val Backspace: ImageVector by lazy {
        icon("backspace", "M22,3H7c-0.69,0 -1.23,0.35 -1.59,0.88L0,12l5.41,8.11c0.36,0.53 0.9,0.89 1.59,0.89h15c1.1,0 2,-0.9 2,-2V5c0,-1.1 -0.9,-2 -2,-2zM19,15.59L17.59,17 14,13.41 10.41,17 9,15.59 12.59,12 9,8.41 10.41,7 14,10.59 17.59,7 19,8.41 15.41,12 19,15.59z")
    }
    val PlayArrow: ImageVector by lazy { icon("play_arrow", "M8,5v14l11,-7z") }
    val Pause: ImageVector by lazy { icon("pause", "M6,19h4V5H6v14zM14,5v14h4V5h-4z") }
    val SkipNext: ImageVector by lazy { icon("skip_next", "M6,18l8.5,-6L6,6v12zM16,6v12h2V6h-2z") }
    val SkipPrevious: ImageVector by lazy { icon("skip_previous", "M6,6h2v12H6zM9.5,12l8.5,6V6z") }
    val MusicNote: ImageVector by lazy { icon("music_note", "M12,3v10.55c-0.59,-0.34 -1.27,-0.55 -2,-0.55 -2.21,0 -4,1.79 -4,4s1.79,4 4,4 4,-1.79 4,-4V7h4V3h-6z") }
    val ChevronRight: ImageVector by lazy { icon("chevron_right", "M10,6L8.59,7.41 13.17,12l-4.58,4.59L10,18l6,-6z") }
}
