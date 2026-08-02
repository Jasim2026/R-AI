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
        super.configureFlutterEngine(flutterEngine)

        Engine.setNativeMinLogSeverity(LogSeverity.WARNING)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkManageStoragePermission" -> {
                    result.success(hasManageStoragePermission())
                }
                "requestManageStoragePermission" -> {
                    requestManageStoragePermission(result)
                }
                "isManageStorageGranted" -> {
                    result.success(isManageStorageGranted())
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> handleInitialize(result)
                "loadModel" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.error("INVALID_ARGS", "Arguments must be a Map", null)
                        return@setMethodCallHandler
                    }
                    handleLoadModel(args, result)
                }
                "unloadModel" -> handleUnloadModel(result)
                "sendMessage" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.error("INVALID_ARGS", "Arguments must be a Map", null)
                        return@setMethodCallHandler
                    }
                    handleSendMessage(args, result)
                }
                "sendMessageAsync" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.error("INVALID_ARGS", "Arguments must be a Map", null)
                        return@setMethodCallHandler
                    }
                    handleSendMessageAsync(args, result)
                }
                "cancel" -> handleCancel(result)
                "readModelMetadata" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.error("INVALID_ARGS", "Arguments must be a Map", null)
                        return@setMethodCallHandler
                    }
                    handleReadModelMetadata(args, result)
                }
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
                result.success(true)
            } else {
                pendingPermissionResult = result
                try {
                    val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                        data = Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivityForResult(intent, MANAGE_STORAGE_REQUEST)
                } catch (e: Exception) {
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
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun handleInitialize(result: MethodChannel.Result) {
        result.success(true)
    }

    private fun handleReadModelMetadata(args: Map<*, *>, result: MethodChannel.Result) {
        scope.launch(Dispatchers.IO) {
            try {
                val modelPath = args["modelPath"] as String

                val backendResults = listOf(
                    "gpu" to Backend.GPU(),
                    "npu" to Backend.NPU(),
                    "cpu" to Backend.CPU()
                ).map { (name, backend) ->
                    async {
                        try {
                            val config = EngineConfig(modelPath = modelPath, backend = backend)
                            val eng = Engine(config)
                            eng.initialize()
                            eng.close()
                            name
                        } catch (_: Exception) {
                            null
                        }
                    }
                }.awaitAll().filterNotNull()

                val metadata = mapOf("supportedBackends" to backendResults)

                withContext(Dispatchers.Main) {
                    result.success(metadata)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
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

                withContext(Dispatchers.Main) {
                    result.success(true)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
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

                withContext(Dispatchers.Main) {
                    result.success(text)
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
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
                        withContext(Dispatchers.Main) {
                            eventSink?.success(mapOf("error" to (e.message ?: "Unknown error")))
                        }
                    }
                    .collect { message ->
                        val text = message.toString()
                        if (text.isNotEmpty()) {
                            withContext(Dispatchers.Main) {
                                eventSink?.success(mapOf("text" to text))
                            }
                        }
                    }

                withContext(Dispatchers.Main) {
                    eventSink?.success(mapOf("done" to true))
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
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
        super.onDestroy()
    }
}
