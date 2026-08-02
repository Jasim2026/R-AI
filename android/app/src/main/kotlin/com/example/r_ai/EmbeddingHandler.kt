package com.example.r_ai

import android.content.Context
import com.google.mediapipe.tasks.text.textembedder.TextEmbedder
import com.google.mediapipe.tasks.text.textembedder.TextEmbedderResult

class EmbeddingHandler(private val context: Context) {
    private var textEmbedder: TextEmbedder? = null
    private var isInitialized = false

    fun initialize(modelPath: String): Boolean {
        return try {
            val options = TextEmbedder.TextEmbedderOptions.builder()
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
            val result: TextEmbedderResult = textEmbedder!!.embed(text)
            val embedding = result.embedding().floatEmbedding()
            val floatArray = FloatArray(embedding.size)
            for (i in embedding.indices) {
                floatArray[i] = embedding[i]
            }
            floatArray
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
