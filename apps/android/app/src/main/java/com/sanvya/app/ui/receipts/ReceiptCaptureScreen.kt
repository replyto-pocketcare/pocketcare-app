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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaType
import com.sanvya.app.ui.components.Muted
import com.sanvya.app.ui.components.SanvyaCard
import com.sanvya.app.ui.components.SanvyaIcon
import com.sanvya.app.theme.SanvyaIcons
import com.sanvya.app.ui.components.SanvyaPage
import com.sanvya.app.ui.components.SanvyaText
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.domain.statements.groupPdfGlyphs
import com.sanvya.app.domain.statements.pdfRowsToText
import com.sanvya.app.pdf.PdfPasswordRequired
import com.sanvya.app.pdf.PdfTextExtractor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.koin.compose.koinInject

/**
 * Receipt capture -- port of apps/web/app/receipts/new/page.tsx.
 *
 * **Extended 2026-08-28** with the three halves that were missing: the
 * entitlement gate, file upload, and PDF bills. Only the AI escalation is
 * still absent (it needs the image bytes plumbed to an edge function; tracked
 * as its own item).
 *
 * The PDF path matters more than it sounds. An emailed bill is the single most
 * accurate input this feature accepts -- it has a real text layer, so it skips
 * OCR entirely and is near-perfect where a photograph is a guess. Web treats it
 * as the special case worth having; a camera-only port had thrown away the best
 * input and kept the worst.
 *
 * Mirrors iOS's ReceiptCaptureView.swift.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReceiptCaptureScreen(
    onBack: () -> Unit,
    onScanned: (scanId: String) -> Unit,
    /** Web's premium card links to /settings; native routes there the same way. */
    onSeePlans: () -> Unit = {},
    viewModel: ReceiptCaptureViewModel = viewModel(),
) {
    val colors = LocalSanvyaColors.current
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val stage by viewModel.stage.collectAsState()
    val savedScanId by viewModel.savedScanId.collectAsState()

    val imageCapture = remember { ImageCapture.Builder().build() }
    val recognizer = remember { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }
    val mainExecutor = remember { ContextCompat.getMainExecutor(context) }

    val canScan by viewModel.canScan.collectAsState()
    val res = sRes()
    val scope = rememberCoroutineScope()
    val pdfExtractor: PdfTextExtractor = koinInject()
    var pendingPdf by remember { mutableStateOf<ByteArray?>(null) }
    var password by rememberSaveable { mutableStateOf("") }

    LaunchedEffect(savedScanId) {
        savedScanId?.let { onScanned(it) }
    }

    /** Read whatever the picker returned. Images go to OCR, PDFs to the text layer. */
    fun ingest(uri: android.net.Uri, pw: String?) {
        viewModel.onUploadStarted()
        scope.launch {
            val bytes = withContext(Dispatchers.IO) {
                runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull()
            }
            if (bytes == null) {
                viewModel.onCaptureFailed(S.Receipts.errorsUnsupportedFile(res))
                return@launch
            }
            val mime = context.contentResolver.getType(uri).orEmpty()
            if (mime == "application/pdf" || looksLikePdf(bytes)) {
                pendingPdf = bytes
                viewModel.onReadingStarted()
                try {
                    val glyphs = pdfExtractor.extract(bytes, pw)
                    viewModel.onPdfText(res, pdfRowsToText(groupPdfGlyphs(glyphs)))
                } catch (_: PdfPasswordRequired) {
                    viewModel.onPasswordRequired()
                } catch (_: Exception) {
                    viewModel.onCaptureFailed(S.Receipts.errorsPdfUnreadable(res))
                }
            } else {
                viewModel.onReadingStarted()
                val bitmap = withContext(Dispatchers.IO) {
                    runCatching { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }.getOrNull()
                }
                if (bitmap == null) {
                    viewModel.onCaptureFailed(S.Receipts.errorsUnsupportedFile(res))
                    return@launch
                }
                recognizer.process(InputImage.fromBitmap(bitmap, 0))
                    .addOnSuccessListener { text -> viewModel.onTextRecognized(text.text) }
                    .addOnFailureListener { viewModel.onCaptureFailed(S.Receipts.errorsUnsupportedFile(res)) }
            }
        }
    }

    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) ingest(uri, null)
    }

    // Web shows a plan card rather than letting the request reach the server
    // and come back rejected. The gate itself is server-side; this is the
    // courtesy that makes a paid feature read as paid rather than as broken.
    if (!canScan) {
        PremiumCard(onBack = onBack, onSeePlans = onSeePlans)
        return
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

    Scaffold(
        containerColor = Color.Black,
        topBar = {
            TopAppBar(
                title = { Text(S.Receipts.captureTitle(sRes()), fontWeight = FontWeight.Bold, color = Color.White) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, contentDescription = S.Translation.commonBack(sRes()), tint = Color.White) }
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
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(20.dp),
                        ) {
                            ShutterButton {
                                viewModel.onCaptureStarted()
                                captureAndRecognize(imageCapture, recognizer, mainExecutor, viewModel)
                            }
                            // Web's second button. The emailed PDF bill is the
                            // most accurate input this feature takes, and a
                            // camera-only screen could not accept one at all.
                            TextButton(onClick = { pickFile.launch(UPLOAD_MIME_TYPES) }) {
                                Text(S.Receipts.captureUpload(res), color = Color.White)
                            }
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
                                    is CaptureStage.Understanding -> S.Receipts.stageUnderstanding(sRes())
                                    else -> S.Data.preparing(sRes())
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
                        message = viewModel.mismatchMessage(res, reason),
                        colors = colors,
                        onEditManually = { viewModel.editManually() },
                        onRetake = { viewModel.retake() },
                    )
                }
                stage is CaptureStage.NeedsPassword -> {
                    PasswordCard(
                        colors = colors,
                        value = password,
                        onValueChange = { password = it },
                        onUnlock = {
                            val bytes = pendingPdf ?: return@PasswordCard
                            viewModel.onReadingStarted()
                            scope.launch {
                                try {
                                    val glyphs = pdfExtractor.extract(bytes, password)
                                    viewModel.onPdfText(res, pdfRowsToText(groupPdfGlyphs(glyphs)))
                                } catch (_: PdfPasswordRequired) {
                                    viewModel.onPasswordRequired()
                                } catch (_: Exception) {
                                    viewModel.onCaptureFailed(S.Receipts.errorsPdfUnreadable(res))
                                }
                            }
                        },
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
                Text(S.Receipts.captureUnclearTitle(sRes()), fontWeight = FontWeight.Bold, color = colors.text)
                Text(message, fontSize = 13.sp, color = colors.text2)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(onClick = onEditManually) { Text(S.Receipts.captureEditManually(sRes())) }
                    OutlinedButton(onClick = onRetake) { Text(S.Receipts.captureRetake(sRes())) }
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

/**
 * What the file picker accepts.
 *
 * The same pair web's upload input accepts: any image, plus PDF.
 * `OpenDocument` is the contract used because -- unlike `GetContent` -- it can
 * express more than one MIME type, which this needs.
 */
private val UPLOAD_MIME_TYPES = arrayOf("image/*", "application/pdf")

/**
 * `%PDF` -- the magic number.
 *
 * The MIME type from a content provider is not trustworthy: files handed over
 * by a mail client or a downloads provider routinely arrive as
 * `application/octet-stream`. Web never sees this because a browser's file
 * input reports the real type. Sniffing the first four bytes is cheap and it is
 * the difference between reading an emailed bill and telling the user their
 * bill is not supported.
 */
private fun looksLikePdf(bytes: ByteArray): Boolean =
    bytes.size >= 4 && bytes[0] == 0x25.toByte() && bytes[1] == 0x50.toByte() &&
        bytes[2] == 0x44.toByte() && bytes[3] == 0x46.toByte()

/** Web's plan card, shown instead of the camera on a free plan. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PremiumCard(onBack: () -> Unit, onSeePlans: () -> Unit) {
    val colors = LocalSanvyaColors.current
    SanvyaPage(title = S.Receipts.captureTitle(sRes())) {
        SanvyaCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(28.dp)) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                SanvyaIcon(SanvyaIcons.lock, size = 30.dp, tint = colors.text2)
                SanvyaText(S.Receipts.premiumTitle(sRes()), SanvyaType.h2)
                Muted(
                    S.Receipts.premiumBody(sRes()),
                    style = SanvyaType.body,
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(onClick = onSeePlans) { Text(S.Receipts.premiumCta(sRes())) }
                TextButton(onClick = onBack) { Text(S.Translation.commonBack(sRes())) }
            }
        }
    }
}

/** Web's password form for an encrypted PDF. */
@Composable
private fun PasswordCard(
    colors: com.sanvya.app.theme.SanvyaColors,
    value: String,
    onValueChange: (String) -> Unit,
    onUnlock: () -> Unit,
) {
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Card(colors = CardDefaults.cardColors(containerColor = colors.surface)) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(S.Receipts.capturePdfPassword(sRes()), fontWeight = FontWeight.Bold, color = colors.text)
                OutlinedTextField(
                    value = value,
                    onValueChange = onValueChange,
                    label = { Text(S.Receipts.capturePasswordPlaceholder(sRes())) },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                )
                Button(onClick = onUnlock, enabled = value.isNotEmpty()) {
                    Text(S.Receipts.captureUnlock(sRes()))
                }
            }
        }
    }
}
