package care.pocket.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import care.pocket.android.theme.PocketCareTheme
import care.pocket.android.ui.navigation.PocketCareNavHost

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            PocketCareTheme {
                PocketCareNavHost()
            }
        }
    }
}
