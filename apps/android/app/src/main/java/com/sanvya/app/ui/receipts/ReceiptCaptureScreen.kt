package com.sanvya.app.ui.receipts

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Camera
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.sanvya.app.theme.LocalSanvyaColors

/**
 * Receipt capture -- real port of apps/web/app/receipts/new/page.tsx's
 * camera path (task #62). See docs/mobile/screen-specs/receipt-scan.md for
 * the documented scope cuts (camera-only, no AI escalation, text-only OCR).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceiptCaptureScreen(
    onBack: () -> Unit,
    onScanned: (scanId: String) -> Unit,
    viewModel: ReceiptCaptureViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val stage by viewModel.stage.collectAsState()
    val savedScanId by viewModel.savedScanId.collectAsState()

    LaunchedEffect(savedScanId) {
        savedScanId?.let { onScanned(it) }
    }

    var hasCameraPermission by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
    }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        hasCameraPermission = granted
    }
    LaunchedEffect(Unit) {
        if (!hasCameraPermission) permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    val imageCapture = remember { ImageCapture.Builder().build() }
    val recognizer = remember { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }
    val mainExecutor = remember { ContextCompat.getMainExecutor(context) }

    Scaffold(
        containerColor = Color.Black,
        topBar = {
            TopAppBar(
                title = { Text("Scan a bill or receipt", fontWeight = FontWeight.Bold, color = Color.White) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, contentDescription = "Back", tint = Color.White) }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Black),
            )
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when {
                !hasCameraPermission -> PermissionNeeded(colors) { permissionLauncher.launch(Manifest.permission.CAMERA) }
                stage is CaptureStage.Idle -> {
                    CameraPreview(
                        imageCapture = imageCapture,
                        lifecycleOwner = lifecycleOwner,
                        modifier = Modifier.fillMaxSize(),
                    )
                    Box(Modifier.fillMaxSize().padding(bottom = 32.dp), contentAlignment = Alignment.BottomCenter) {
                        ShutterButton {
                            viewModel.onCaptureStarted()
                            captureAndRecognize(imageCapture, recognizer, mainExecutor, viewModel)
                        }
                    }
                    Text(
                        "Photographs never leave your device -- they're read here and never saved.",
                        color = Color.White.copy(alpha = 0.7f),
                        fontSize = 11.sp,
                        modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 100.dp).padding(horizontal = 24.dp),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                }
                stage is CaptureStage.Preparing || stage is CaptureStage.Reading || stage is CaptureStage.Understanding -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            CircularProgressIndicator(color = colors.accent)
                            Text(
                                when (stage) {
                                    is CaptureStage.Reading -> "Reading…"
                                    is CaptureStage.Understanding -> "Making sense of it…"
                                    else -> "Preparing…"
                                },
                                color = Color.White,
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                    }
                }
                stage is CaptureStage.Mismatch -> {
                    val reason = (stage as CaptureStage.Mismatch).reason
                    MismatchCard(
                        message = viewModel.mismatchMessage(reason),
                        colors = colors,
                        onEditManually = { viewModel.editManually() },
                        onRetake = { viewModel.retake() },
                    )
                }
                stage is CaptureStage.Error -> {
                    val message = (stage as CaptureStage.Error).message
                    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            Text(message, color = Color.White, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                            Button(onClick = { viewModel.retake() }) { Text("Try again") }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CameraPreview(imageCapture: ImageCapture, lifecycleOwner: androidx.lifecycle.LifecycleOwner, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            val previewView = PreviewView(ctx)
            val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
            cameraProviderFuture.addListener({
                val cameraProvider = cameraProviderFuture.get()
                val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
                try {
                    cameraProvider.unbindAll()
                    cameraProvider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, imageCapture)
                } catch (_: Exception) {
                    // Nothing sensible to show here beyond leaving the last-bound
                    // (or blank) preview -- a truly cameraless device already
                    // showed PermissionNeeded/an OS-level "no camera" dialog.
                }
            }, ContextCompat.getMainExecutor(ctx))
            previewView
        },
    )
}

@Composable
private fun ShutterButton(onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(76.dp)
            .background(Color.White.copy(alpha = 0.25f), CircleShape)
            .padding(6.dp)
            .background(Color.White, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        IconButton(onClick = onClick) {
            Icon(Icons.Default.Camera, contentDescription = "Capture", tint = Color.Black, modifier = Modifier.size(32.dp))
        }
    }
}

@Composable
private fun PermissionNeeded(colors: com.sanvya.app.theme.SanvyaColors, onRequest: () -> Unit) {
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Camera access needed", color = Color.White, fontWeight = FontWeight.Bold)
            Text(
                "Sanvya needs your camera to scan a bill or receipt. Nothing is uploaded or saved.",
                color = Color.White.copy(alpha = 0.75f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                fontSize = 13.sp,
            )
            Button(onClick = onRequest) { Text("Allow camera access") }
        }
    }
}

@Composable
private fun MismatchCard(message: String, colors: com.sanvya.app.theme.SanvyaColors, onEditManually: () -> Unit, onRetake: () -> Unit) {
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Card(colors = CardDefaults.cardColors(containerColor = colors.surface)) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text("We couldn't read this cleanly", fontWeight = FontWeight.Bold, color = colors.text)
                Text(message, fontSize = 13.sp, color = colors.text2)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(onClick = onEditManually) { Text("Edit it myself") }
                    OutlinedButton(onClick = onRetake) { Text("Retake") }
                }
            }
        }
    }
}

/** Captures one frame, runs on-device OCR, and hands the recognized text to
 * the ViewModel. JPEG-format ImageProxy -> Bitmap -> rotated Bitmap ->
 * InputImage: ML Kit's fromMediaImage() wants YUV_420_888, which
 * ImageCapture.OnImageCapturedCallback does not hand back by default (it
 * captures JPEG), so this goes through Bitmap instead -- correct for a
 * single still capture, not a live-frame analyzer where YUV would matter
 * for performance. */
private fun captureAndRecognize(
    imageCapture: ImageCapture,
    recognizer: com.google.mlkit.vision.text.TextRecognizer,
    executor: java.util.concurrent.Executor,
    viewModel: ReceiptCaptureViewModel,
) {
    imageCapture.takePicture(executor, object : ImageCapture.OnImageCapturedCallback() {
        override fun onCaptureSuccess(image: ImageProxy) {
            viewModel.onReadingStarted()
            try {
                val bitmap = imageProxyToBitmap(image)
                val rotation = image.imageInfo.rotationDegrees
                val rotated = if (rotation != 0) rotateBitmap(bitmap, rotation) else bitmap
                val inputImage = InputImage.fromBitmap(rotated, 0)
                recognizer.process(inputImage)
                    .addOnSuccessListener { text -> viewModel.onTextRecognized(text.text) }
                    .addOnFailureListener { e -> viewModel.onCaptureFailed(e.message ?: "Couldn't read this receipt.") }
            } catch (e: Exception) {
                viewModel.onCaptureFailed(e.message ?: "Couldn't read this receipt.")
            } finally {
                image.close()
            }
        }

        override fun onError(exception: ImageCaptureException) {
            viewModel.onCaptureFailed(exception.message ?: "Couldn't use the camera.")
        }
    })
}

private fun imageProxyToBitmap(image: ImageProxy): Bitmap {
    val buffer = image.planes[0].buffer
    val bytes = ByteArray(buffer.remaining())
    buffer.get(bytes)
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        ?: throw IllegalStateException("Couldn't decode the captured photo.")
}

private fun rotateBitmap(bitmap: Bitmap, degrees: Int): Bitmap {
    val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
    return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
}
