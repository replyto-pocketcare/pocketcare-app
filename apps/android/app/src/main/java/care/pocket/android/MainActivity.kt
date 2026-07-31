package care.pocket.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import care.pocket.domain.DomainSkeleton

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            PocketCareSkeleton()
        }
    }
}

@Composable
fun PocketCareSkeleton() {
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                // Proves :app -> :domain wires up, same spirit as the old
                // RN scaffold's canary screen. Real screens start at
                // Phase 3 (plan §7) once Phase 0/1 land.
                Text(if (DomainSkeleton.READY) "PocketCare — Android skeleton (P0.2)" else "domain not wired")
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
fun PocketCareSkeletonPreview() {
    PocketCareSkeleton()
}
