package com.example.r_ai

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.LogSeverity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.rai/litert"
    private val EVENT_CHANNEL = "com.rai/litert_stream"
    private val EMBEDDING_CHANNEL = "com.rai/embedding"

    private var engine: Engine? = null
    private var conversation: Conversation? = null
    private var generationJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.Main + Job())

    private var eventSink: EventChannel.EventSink? = null
    private var embeddingHandler: EmbeddingHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        Engine.setNativeMinLogSeverity(LogSeverity.WARNING)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> handleInitialize(result)
                "loadModel" -> handleLoadModel(call.arguments as Map<*, *>, result)
                "unloadModel" -> handleUnloadModel(result)
                "sendMessage" -> handleSendMessage(call.arguments as Map<*, *>, result)
                "sendMessageAsync" -> handleSendMessageAsync(call.arguments as Map<*, *>, result)
                "cancel" -> handleCancel(result)
                "readModelMetadata" -> handleReadModelMetadata(call.arguments as Map<*, *>, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EMBEDDING_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initEmbedding" -> handleInitEmbedding(call.arguments as Map<*, *>, result)
                "embed" -> handleEmbed(call.arguments as Map<*, *>, result)
                "embedBatch" -> handleEmbedBatch(call.arguments as Map<*, *>, result)
                "closeEmbedding" -> handleCloseEmbedding(result)
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    private fun handleInitialize(result: MethodChannel.Result) {
        result.success(true)
    }

    private fun handleInitEmbedding(args: Map<*, *>, result: MethodChannel.Result) {
        scope.launch(Dispatchers.IO) {
            try {
                val modelPath = args["modelPath"] as String
                val handler = EmbeddingHandler(applicationContext)
                val success = handler.initialize(modelPath)
                if (success) {
                    embeddingHandler = handler
                }
                scope.launch(Dispatchers.Main) {
                    result.success(success)
                }
            } catch (e: Exception) {
                scope.launch(Dispatchers.Main) {
                    result.error("EMBEDDING_INIT_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleEmbed(args: Map<*, *>, result: MethodChannel.Result) {
        val handler = embeddingHandler
        if (handler == null) {
            result.error("EMBEDDING_NOT_INIT", "Embedding model not loaded", null)
            return
        }

        scope.launch(Dispatchers.Default) {
            try {
                val text = args["text"] as String
                val embedding = handler.embed(text)
                if (embedding != null) {
                    scope.launch(Dispatchers.Main) {
                        result.success(embedding.toList())
                    }
                } else {
                    scope.launch(Dispatchers.Main) {
                        result.error("EMBED_FAILED", "Failed to embed text", null)
                    }
                }
            } catch (e: Exception) {
                scope.launch(Dispatchers.Main) {
                    result.error("EMBED_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleEmbedBatch(args: Map<*, *>, result: MethodChannel.Result) {
        val handler = embeddingHandler
        if (handler == null) {
            result.error("EMBEDDING_NOT_INIT", "Embedding model not loaded", null)
            return
        }

        scope.launch(Dispatchers.Default) {
            try {
                val texts = args["texts"] as List<String>
                val embeddings = handler.embedBatch(texts)
                val validEmbeddings = embeddings.filterNotNull().map { it.toList() }
                scope.launch(Dispatchers.Main) {
                    result.success(validEmbeddings)
                }
            } catch (e: Exception) {
                scope.launch(Dispatchers.Main) {
                    result.error("EMBED_BATCH_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleCloseEmbedding(result: MethodChannel.Result) {
        embeddingHandler?.close()
        embeddingHandler = null
        result.success(true)
    }

    private fun handleReadModelMetadata(args: Map<*, *>, result: MethodChannel.Result) {
        scope.launch(Dispatchers.IO) {
            try {
                val modelPath = args["modelPath"] as String
                val supportedBackends = mutableListOf<String>()

                for (pair in listOf(
                    "gpu" to Backend.GPU(),
                    "npu" to Backend.NPU(),
                    "cpu" to Backend.CPU()
                )) {
                    val (name, backend) = pair
                    try {
                        val config = EngineConfig(modelPath = modelPath, backend = backend)
                        val eng = Engine(config)
                        eng.initialize()
                        eng.close()
                        supportedBackends.add(name)
                    } catch (_: Exception) {}
                }

                val metadata = mapOf("supportedBackends" to supportedBackends)

                scope.launch(Dispatchers.Main) {
                    result.success(metadata)
                }
            } catch (e: Exception) {
                scope.launch(Dispatchers.Main) {
                    result.error("METADATA_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleLoadModel(args: Map<*, *>, result: MethodChannel.Result) {
        scope.launch(Dispatchers.IO) {
            try {
                conversation?.close()
                conversation = null
                engine?.close()
                engine = null

                val modelPath = args["modelPath"] as String
                val backendName = args["backend"] as? String ?: "gpu"
                val cacheDir = args["cacheDir"] as? String

                val backend = when (backendName) {
                    "gpu" -> Backend.GPU()
                    "npu" -> Backend.NPU()
                    else -> Backend.CPU()
                }

                val engineConfig = EngineConfig(
                    modelPath = modelPath,
                    backend = backend,
                    cacheDir = cacheDir
                )

                val eng = Engine(engineConfig)
                eng.initialize()
                engine = eng

                val conv = eng.createConversation()
                conversation = conv

                scope.launch(Dispatchers.Main) {
                    result.success(true)
                }
            } catch (e: Exception) {
                scope.launch(Dispatchers.Main) {
                    result.error("LOAD_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleUnloadModel(result: MethodChannel.Result) {
        try {
            generationJob?.cancel()
            generationJob = null
            conversation?.close()
            conversation = null
            engine?.close()
            engine = null
            result.success(true)
        } catch (e: Exception) {
            result.error("UNLOAD_FAILED", e.message, null)
        }
    }

    private fun handleSendMessage(args: Map<*, *>, result: MethodChannel.Result) {
        val conv = conversation
        if (conv == null) {
            result.error("NO_CONVERSATION", "No conversation active", null)
            return
        }

        scope.launch(Dispatchers.Default) {
            try {
                val content = args["content"] as String
                val response = conv.sendMessage(content)
                val text = response.toString()

                scope.launch(Dispatchers.Main) {
                    result.success(text)
                }
            } catch (e: Exception) {
                scope.launch(Dispatchers.Main) {
                    result.error("GENERATION_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleSendMessageAsync(args: Map<*, *>, result: MethodChannel.Result) {
        val conv = conversation
        if (conv == null) {
            result.error("NO_CONVERSATION", "No conversation active", null)
            return
        }

        generationJob?.cancel()
        generationJob = null

        result.success(true)

        generationJob = scope.launch(Dispatchers.Default) {
            try {
                val content = args["content"] as String

                conv.sendMessageAsync(content)
                    .catch { e ->
                        scope.launch(Dispatchers.Main) {
                            eventSink?.success(mapOf("error" to (e.message ?: "Unknown error")))
                        }
                    }
                    .collect { message ->
                        val text = message.toString()
                        if (text.isNotEmpty()) {
                            scope.launch(Dispatchers.Main) {
                                eventSink?.success(mapOf("text" to text))
                            }
                        }
                    }

                scope.launch(Dispatchers.Main) {
                    eventSink?.success(mapOf("done" to true))
                }
            } catch (e: Exception) {
                scope.launch(Dispatchers.Main) {
                    eventSink?.success(mapOf("error" to (e.message ?: "Unknown error")))
                }
            }
        }
    }

    private fun handleCancel(result: MethodChannel.Result) {
        generationJob?.cancel()
        generationJob = null
        result.success(true)
    }

    override fun onDestroy() {
        generationJob?.cancel()
        scope.cancel()
        conversation?.close()
        engine?.close()
        embeddingHandler?.close()
        super.onDestroy()
    }
}
