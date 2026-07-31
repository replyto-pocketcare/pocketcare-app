package care.pocket.android.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Clay50 = Color(0xFFFAF6F1)
val Clay100 = Color(0xFFF1E8DE)
val Clay200 = Color(0xEFE4D3C1)
val Terracotta = Color(0xFFB06A4F)
val TerracottaSoft = Color(0xFFC98A72)
val Olive600 = Color(0xFF5F6647)
val Sage = Color(0xFF9CAE8E)
val Ink = Color(0xFF2B2723)
val InkSoft = Color(0xFF6B6459)
val Cream = Color(0xFFFFFDF9)
val DarkBackground = Color(0xFF211E1A)
val DarkSurface = Color(0xFF2B2723)

private val DarkColorScheme = darkColorScheme(
    primary = TerracottaSoft,
    secondary = Sage,
    background = DarkBackground,
    surface = DarkSurface,
    onPrimary = Ink,
    onSecondary = Cream,
    onBackground = Clay50,
    onSurface = Clay50,
)

private val LightColorScheme = lightColorScheme(
    primary = Terracotta,
    secondary = Olive600,
    background = Clay50,
    surface = Cream,
    onPrimary = Cream,
    onSecondary = Cream,
    onBackground = Ink,
    onSurface = Ink,
)

@Composable
fun PocketCareTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    MaterialTheme(
        colorScheme = colorScheme,
        content = content
    )
}
