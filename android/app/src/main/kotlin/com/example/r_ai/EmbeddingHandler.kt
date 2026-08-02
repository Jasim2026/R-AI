package com.example.r_ai

import android.content.Context
import android.os.ParcelFileDescriptor
import android.util.Log
import com.google.mediapipe.tasks.text.textembedder.TextEmbedder
import com.google.mediapipe.tasks.text.textembedder.TextEmbedderResult
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class EmbeddingHandler(private val context: Context) {
    private var textEmbedder: TextEmbedder? = null
    private var isInitialized = false
    private var embeddingDimension = 0
    private var currentModelPath: String? = null
    private var currentDescriptor: ParcelFileDescriptor? = null

    companion object {
        private const val TAG = "EmbeddingHandler"
        private val LOG_DIR = File("/storage/emulated/0/R-Ai")
        private val LOG_FILE = File(LOG_DIR, "log.txt")

        fun log(message: String, throwable: Throwable? = null) {
            try {
                if (!LOG_DIR.exists()) {
                    LOG_DIR.mkdirs()
                }
                val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
                val logMessage = buildString {
                    append("[$timestamp] $TAG: $message")
                    if (throwable != null) {
                        append("\n${Log.getStackTraceString(throwable)}")
                    }
                    append("\n")
                }
                FileOutputStream(LOG_FILE, true).use { fos ->
                    fos.write(logMessage.toByteArray())
                }
            } catch (_: Exception) {
                // Silently fail if we can't write logs
            }
        }
    }

    fun initialize(modelPath: String): Boolean {
        log("initialize() called with modelPath: $modelPath")
        return try {
            close()

            val targetFile = File(context.filesDir, "embedding_model")
            val sourceFile = File(modelPath)

            log("Source file exists: ${sourceFile.exists()}, size: ${if (sourceFile.exists()) sourceFile.length() else 0}")
            log("Target file path: ${targetFile.absolutePath}")

            if (!sourceFile.exists()) {
                log("ERROR: Source file does not exist: $modelPath")
                isInitialized = false
                return false
            }

            if (sourceFile.absolutePath != currentModelPath || !targetFile.exists()) {
                log("Copying model to internal storage...")
                sourceFile.copyTo(targetFile, overwrite = true)
                currentModelPath = sourceFile.absolutePath
                log("Model copied successfully. Target size: ${targetFile.length()}")
            }

            log("Opening ParcelFileDescriptor...")
            val descriptor = ParcelFileDescriptor.open(
                targetFile,
                ParcelFileDescriptor.MODE_READ_ONLY
            )
            currentDescriptor = descriptor

            log("Creating TextEmbedder options with fd: ${descriptor.fd}")
            val baseOptions = com.google.mediapipe.tasks.core.BaseOptions.builder()
                .setModelAssetFileDescriptor(descriptor.fd)
                .build()

            val options = TextEmbedder.TextEmbedderOptions.builder()
                .setBaseOptions(baseOptions)
                .build()

            log("Creating TextEmbedder from options...")
            textEmbedder = TextEmbedder.createFromOptions(context, options)
            log("TextEmbedder created successfully")

            log("Running test embedding...")
            val testResult = textEmbedder!!.embed("test")
            val floats = testResult.embeddingResult().embeddings()[0].floatEmbedding()
            embeddingDimension = floats.size
            log("Test embedding successful. Dimension: $embeddingDimension")

            isInitialized = true
            true
        } catch (e: Exception) {
            log("ERROR initializing embedding handler", e)
            isInitialized = false
            embeddingDimension = 0
            false
        }
    }

    fun getEmbeddingDimension(): Int = embeddingDimension

    fun embed(text: String): FloatArray? {
        if (!isInitialized || textEmbedder == null) return null

        return try {
            val result: TextEmbedderResult = textEmbedder!!.embed(text)
            val embeddingResult = result.embeddingResult()
            val embedding = embeddingResult.embeddings()[0]
            val floats = embedding.floatEmbedding()
            FloatArray(floats.size) { floats[it] }
        } catch (e: Exception) {
            log("ERROR embedding text", e)
            null
        }
    }

    fun embedBatch(texts: List<String>): List<FloatArray?> {
        return texts.map { embed(it) }
    }

    fun close() {
        textEmbedder?.close()
        textEmbedder = null
        currentDescriptor?.close()
        currentDescriptor = null
        isInitialized = false
        embeddingDimension = 0
    }

    fun isReady(): Boolean = isInitialized
}
