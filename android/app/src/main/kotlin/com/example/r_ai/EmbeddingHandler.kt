package com.example.r_ai

import android.content.Context
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.text.textembedder.TextEmbedder
import com.google.mediapipe.tasks.text.textembedder.TextEmbedderOptions
import com.google.mediapipe.tasks.text.textembedder.TextEmbedderResult
import android.graphics.Bitmap
import android.graphics.Color
import java.nio.FloatBuffer

class EmbeddingHandler(private val context: Context) {
    private var textEmbedder: TextEmbedder? = null
    private var isInitialized = false

    fun initialize(modelPath: String): Boolean {
        return try {
            val options = TextEmbedderOptions.builder()
                .setBaseOptions(
                    com.google.mediapipe.tasks.core.BaseOptions.builder()
                        .setModelAssetPath(modelPath)
                        .build()
                )
                .build()

            textEmbedder = TextEmbedder.createFromOptions(context, options)
            isInitialized = true
            true
        } catch (e: Exception) {
            false
        }
    }

    fun embed(text: String): FloatArray? {
        if (!isInitialized || textEmbedder == null) return null

        return try {
            val result = textEmbedder!!.embed(text)
            result.embeddingResult().embeddings()[0].floatEmbedding().toFloatArray()
        } catch (e: Exception) {
            null
        }
    }

    fun embedBatch(texts: List<String>): List<FloatArray?> {
        return texts.map { embed(it) }
    }

    fun close() {
        textEmbedder?.close()
        textEmbedder = null
        isInitialized = false
    }

    fun isReady(): Boolean = isInitialized
}
