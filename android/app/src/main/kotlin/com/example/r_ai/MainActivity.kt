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

    private var engine: Engine? = null
    private var conversation: Conversation? = null
    private var generationJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.Main + Job())

    private var eventSink: EventChannel.EventSink? = null

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

    private fun handleLoadModel(args: Map<*, *>, result: MethodChannel.Result) {
        scope.launch(Dispatchers.IO) {
            try {
                val modelPath = args["modelPath"] as String
                val backendName = args["backend"] as? String ?: "GPU"
                val cacheDir = args["cacheDir"] as? String

                val backend = when (backendName) {
                    "GPU" -> Backend.GPU()
                    "NPU" -> Backend.NPU()
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

        scope.launch(Dispatchers.IO) {
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

        result.success(true)

        generationJob?.cancel()
        generationJob = scope.launch(Dispatchers.IO) {
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
                    eventSink?.success(mapOf("error" to e.message))
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
        scope.cancel()
        conversation?.close()
        engine?.close()
        super.onDestroy()
    }
}