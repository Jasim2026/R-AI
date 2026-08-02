package com.example.r_ai

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
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
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.cancel
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.rai/litert"
    private val EVENT_CHANNEL = "com.rai/litert_stream"
    private val PERMISSION_CHANNEL = "com.rai/permissions"

    private var engine: Engine? = null
    private var conversation: Conversation? = null
    private var generationJob: kotlinx.coroutines.Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    companion object {
        private const val TAG = "MainActivity"
        private const val MANAGE_STORAGE_REQUEST = 1001
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
                        append("\n${android.util.Log.getStackTraceString(throwable)}")
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        log("Configuring Flutter engine...")
        super.configureFlutterEngine(flutterEngine)

        log("Setting LiteRT-LM native min log severity to WARNING")
        Engine.setNativeMinLogSeverity(LogSeverity.WARNING)

        log("Setting up permission channel: $PERMISSION_CHANNEL")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkManageStoragePermission" -> {
                    val granted = hasManageStoragePermission()
                    log("Permission check: MANAGE_STORAGE = $granted")
                    result.success(granted)
                }
                "requestManageStoragePermission" -> {
                    log("Requesting MANAGE_STORAGE permission...")
                    requestManageStoragePermission(result)
                }
                "isManageStorageGranted" -> {
                    val granted = isManageStorageGranted()
                    log("Permission isManageStorageGranted: $granted")
                    result.success(granted)
                }
                else -> {
                    log("Unknown permission method: ${call.method}")
                    result.notImplemented()
                }
            }
        }

        log("Setting up method channel: $METHOD_CHANNEL")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            log("Method call received: ${call.method}")
            when (call.method) {
                "initialize" -> handleInitialize(result)
                "loadModel" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        log("ERROR: loadModel called with null arguments")
                        result.error("INVALID_ARGS", "Arguments must be a Map", null)
                        return@setMethodCallHandler
                    }
                    log("loadModel args: modelPath=${args["modelPath"]}, backend=${args["backend"]}, cacheDir=${args["cacheDir"]}")
                    handleLoadModel(args, result)
                }
                "unloadModel" -> handleUnloadModel(result)
                "sendMessage" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        log("ERROR: sendMessage called with null arguments")
                        result.error("INVALID_ARGS", "Arguments must be a Map", null)
                        return@setMethodCallHandler
                    }
                    val content = args["content"] as? String ?: ""
                    log("sendMessage: content length=${content.length}, preview=\"${content.take(100)}\"")
                    handleSendMessage(args, result)
                }
                "sendMessageAsync" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        log("ERROR: sendMessageAsync called with null arguments")
                        result.error("INVALID_ARGS", "Arguments must be a Map", null)
                        return@setMethodCallHandler
                    }
                    val content = args["content"] as? String ?: ""
                    log("sendMessageAsync: content length=${content.length}, maxTokens=${args["maxTokens"]}, temp=${args["temperature"]}, topP=${args["topP"]}, topK=${args["topK"]}")
                    handleSendMessageAsync(args, result)
                }
                "cancel" -> handleCancel(result)
                "readModelMetadata" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        log("ERROR: readModelMetadata called with null arguments")
                        result.error("INVALID_ARGS", "Arguments must be a Map", null)
                        return@setMethodCallHandler
                    }
                    log("readModelMetadata: modelPath=${args["modelPath"]}")
                    handleReadModelMetadata(args, result)
                }
                else -> {
                    log("Unknown method: ${call.method}")
                    result.notImplemented()
                }
            }
        }

        log("Setting up event channel: $EVENT_CHANNEL")
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    log("EventChannel onListen: sink connected")
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    log("EventChannel onCancel: sink disconnected")
                    eventSink = null
                }
            }
        )
        log("Flutter engine configuration complete")
    }

    private fun hasManageStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true
        }
    }

    private fun isManageStorageGranted(): Boolean {
        return hasManageStoragePermission()
    }

    private fun requestManageStoragePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (Environment.isExternalStorageManager()) {
                log("MANAGE_STORAGE already granted")
                result.success(true)
            } else {
                log("Requesting MANAGE_STORAGE permission via settings...")
                pendingPermissionResult = result
                try {
                    val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                        data = Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    log("Opening permission settings for package: $packageName")
                    startActivityForResult(intent, MANAGE_STORAGE_REQUEST)
                } catch (e: Exception) {
                    log("Failed to open package-specific settings, trying general settings", e)
                    try {
                        val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivityForResult(intent, MANAGE_STORAGE_REQUEST)
                    } catch (e2: Exception) {
                        log("ERROR: Failed to open storage permission settings", e2)
                        result.error("PERMISSION_ERROR", "Failed to open permission settings", null)
                    }
                }
            }
        } else {
            log("MANAGE_STORAGE not required for SDK < 30")
            result.success(true)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == MANAGE_STORAGE_REQUEST) {
            val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Environment.isExternalStorageManager()
            } else {
                true
            }
            log("Permission result: MANAGE_STORAGE = $granted")
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun handleInitialize(result: MethodChannel.Result) {
        log("handleInitialize: Initializing LiteRT engine...")
        result.success(true)
        log("handleInitialize: Complete")
    }

    private fun handleReadModelMetadata(args: Map<*, *>, result: MethodChannel.Result) {
        scope.launch(Dispatchers.IO) {
            try {
                val modelPath = args["modelPath"] as String
                log("handleReadModelMetadata: Probing backends for $modelPath")

                val backendResults = listOf(
                    "gpu" to Backend.GPU(),
                    "npu" to Backend.NPU(),
                    "cpu" to Backend.CPU()
                ).map { (name, backend) ->
                    async {
                        try {
                            log("Probing backend: $name...")
                            val config = EngineConfig(modelPath = modelPath, backend = backend)
                            val eng = Engine(config)
                            eng.initialize()
                            eng.close()
                            log("Backend $name: SUPPORTED")
                            name
                        } catch (e: Exception) {
                            log("Backend $name: NOT SUPPORTED (${e.message})")
                            null
                        }
                    }
                }.awaitAll().filterNotNull()

                log("Supported backends: $backendResults")
                val metadata = mapOf("supportedBackends" to backendResults)

                withContext(Dispatchers.Main) {
                    result.success(metadata)
                }
            } catch (e: Exception) {
                log("ERROR: readModelMetadata failed", e)
                withContext(Dispatchers.Main) {
                    result.error("METADATA_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleLoadModel(args: Map<*, *>, result: MethodChannel.Result) {
        scope.launch(Dispatchers.IO) {
            try {
                log("handleLoadModel: Closing previous engine/conversation...")
                conversation?.close()
                conversation = null
                engine?.close()
                engine = null

                val modelPath = args["modelPath"] as String
                val backendName = args["backend"] as? String ?: "gpu"
                val cacheDir = args["cacheDir"] as? String

                log("handleLoadModel: modelPath=$modelPath, backend=$backendName, cacheDir=$cacheDir")

                val backend = when (backendName) {
                    "gpu" -> {
                        log("Using GPU backend")
                        Backend.GPU()
                    }
                    "npu" -> {
                        log("Using NPU backend")
                        Backend.NPU()
                    }
                    else -> {
                        log("Using CPU backend")
                        Backend.CPU()
                    }
                }

                log("Creating EngineConfig...")
                val engineConfig = EngineConfig(
                    modelPath = modelPath,
                    backend = backend,
                    cacheDir = cacheDir
                )

                log("Creating Engine...")
                val eng = Engine(engineConfig)
                log("Initializing Engine...")
                eng.initialize()
                engine = eng
                log("Engine initialized successfully")

                log("Creating Conversation...")
                val conv = eng.createConversation()
                conversation = conv
                log("Conversation created successfully")

                log("handleLoadModel: Model loaded successfully")
                withContext(Dispatchers.Main) {
                    result.success(true)
                }
            } catch (e: Exception) {
                log("ERROR: handleLoadModel failed", e)
                withContext(Dispatchers.Main) {
                    result.error("LOAD_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleUnloadModel(result: MethodChannel.Result) {
        log("handleUnloadModel: Unloading model...")
        try {
            generationJob?.cancel()
            generationJob = null
            conversation?.close()
            conversation = null
            engine?.close()
            engine = null
            log("handleUnloadModel: Model unloaded successfully")
            result.success(true)
        } catch (e: Exception) {
            log("ERROR: handleUnloadModel failed", e)
            result.error("UNLOAD_FAILED", e.message, null)
        }
    }

    private fun handleSendMessage(args: Map<*, *>, result: MethodChannel.Result) {
        val conv = conversation
        if (conv == null) {
            log("ERROR: handleSendMessage: No conversation active")
            result.error("NO_CONVERSATION", "No conversation active", null)
            return
        }

        scope.launch(Dispatchers.Default) {
            try {
                val content = args["content"] as String
                log("handleSendMessage: Sending message (${content.length} chars)")
                log("handleSendMessage: Preview: \"${content.take(100)}\"")

                val response = conv.sendMessage(content)
                val text = response.toString()
                log("handleSendMessage: Response received (${text.length} chars)")
                log("handleSendMessage: Response preview: \"${text.take(100)}\"")

                withContext(Dispatchers.Main) {
                    result.success(text)
                }
            } catch (e: Exception) {
                log("ERROR: handleSendMessage failed", e)
                withContext(Dispatchers.Main) {
                    result.error("GENERATION_FAILED", e.message, null)
                }
            }
        }
    }

    private fun handleSendMessageAsync(args: Map<*, *>, result: MethodChannel.Result) {
        val conv = conversation
        if (conv == null) {
            log("ERROR: handleSendMessageAsync: No conversation active")
            result.error("NO_CONVERSATION", "No conversation active", null)
            return
        }

        generationJob?.cancel()
        generationJob = null

        log("handleSendMessageAsync: Starting async generation...")
        result.success(true)

        generationJob = scope.launch(Dispatchers.Default) {
            try {
                val content = args["content"] as String
                log("handleSendMessageAsync: Sending message (${content.length} chars)")
                log("handleSendMessageAsync: Preview: \"${content.take(100)}\"")

                var tokenCount = 0
                conv.sendMessageAsync(content)
                    .catch { e ->
                        log("ERROR: Stream error during generation", e)
                        withContext(Dispatchers.Main) {
                            eventSink?.success(mapOf("error" to (e.message ?: "Unknown error")))
                        }
                    }
                    .collect { message ->
                        val text = message.toString()
                        tokenCount++
                        if (tokenCount % 50 == 0) {
                            log("handleSendMessageAsync: Stream token #$tokenCount")
                        }
                        if (text.isNotEmpty()) {
                            withContext(Dispatchers.Main) {
                                eventSink?.success(mapOf("text" to text))
                            }
                        }
                    }

                log("handleSendMessageAsync: Generation complete, $tokenCount tokens sent")
                withContext(Dispatchers.Main) {
                    eventSink?.success(mapOf("done" to true))
                }
            } catch (e: Exception) {
                log("ERROR: handleSendMessageAsync failed", e)
                withContext(Dispatchers.Main) {
                    eventSink?.success(mapOf("error" to (e.message ?: "Unknown error")))
                }
            }
        }
    }

    private fun handleCancel(result: MethodChannel.Result) {
        log("handleCancel: Cancelling generation...")
        generationJob?.cancel()
        generationJob = null
        log("handleCancel: Generation cancelled")
        result.success(true)
    }

    override fun onDestroy() {
        log("onDestroy: Cleaning up...")
        generationJob?.cancel()
        scope.cancel()
        conversation?.close()
        engine?.close()
        log("onDestroy: Cleanup complete")
        super.onDestroy()
    }
}
