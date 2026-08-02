package com.sanvya.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.sanvya.app.theme.SanvyaTheme
import com.sanvya.app.ui.navigation.SanvyaNavHost
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            SanvyaTheme {
                SanvyaNavHost()
            }
        }
    }
}
