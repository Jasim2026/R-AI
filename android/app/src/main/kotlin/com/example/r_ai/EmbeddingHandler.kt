package com.example.r_ai

import android.content.Context
import com.google.mediapipe.tasks.text.textembedder.TextEmbedder
import com.google.mediapipe.tasks.text.textembedder.TextEmbedderResult

class EmbeddingHandler(private val context: Context) {
    private var textEmbedder: TextEmbedder? = null
    private var isInitialized = false
    private var embeddingDimension = 0

    fun initialize(modelPath: String): Boolean {
        return try {
            close()

            val options = TextEmbedder.TextEmbedderOptions.builder()
                .setBaseOptions(
                    com.google.mediapipe.tasks.core.BaseOptions.builder()
                        .setModelAssetPath(modelPath)
                        .build()
                )
                .build()

            textEmbedder = TextEmbedder.createFromOptions(context, options)

            // Probe dimension with a test embedding
            val testResult = textEmbedder!!.embed("test")
            val floats = testResult.embeddingResult().embeddings()[0].floatEmbedding()
            embeddingDimension = floats.size

            isInitialized = true
            true
        } catch (e: Exception) {
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
        embeddingDimension = 0
    }

    fun isReady(): Boolean = isInitialized
}
