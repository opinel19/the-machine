package com.emirozkunduz.person_of_interest

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.FloatBuffer

/**
 * Runs the bundled face-embedding model (MobileFaceNet, ONNX) for Dart.
 *
 * `embed` takes an aligned 112x112 face as interleaved RGB bytes and returns
 * its L2-normalised 512-d embedding. The model has the input normalisation,
 * flip test-time augmentation and L2 normalisation built in, exactly like the
 * iOS Core ML version. Calls run on a background task queue.
 */
class FaceEmbedderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private companion object {
        const val SIDE = 112
        const val PLANE = SIDE * SIDE
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var environment: OrtEnvironment? = null
    private var session: OrtSession? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        val queue = binding.binaryMessenger.makeBackgroundTaskQueue()
        channel = MethodChannel(binding.binaryMessenger, "poi/face_embedder", StandardMethodCodec.INSTANCE, queue)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        session?.close()
        session = null
    }

    @Synchronized
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "load" -> {
                    load()
                    result.success(null)
                }
                "embed" -> {
                    val rgb = call.arguments as? ByteArray
                    if (rgb == null || rgb.size != PLANE * 3) {
                        result.error("bad_input", "expected 112x112 RGB bytes", null)
                    } else {
                        result.success(embed(rgb))
                    }
                }
                // Launch-time test hooks are an iOS thing.
                "launchEnvironment" -> result.success(emptyMap<String, String>())
                "log" -> {
                    Log.i("machine", call.arguments as? String ?: "")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("embedder", e.message, null)
        }
    }

    private fun load() {
        if (session != null) return
        val env = OrtEnvironment.getEnvironment()
        val model = context.assets.open("FaceEmbedder.onnx").use { it.readBytes() }
        val options = OrtSession.SessionOptions().apply { setIntraOpNumThreads(2) }
        session = env.createSession(model, options)
        environment = env
    }

    private fun embed(rgb: ByteArray): FloatArray {
        load()
        // Interleaved HWC bytes -> planar CHW floats in 0..255 (the model normalises).
        val input = FloatBuffer.allocate(PLANE * 3)
        for (i in 0 until PLANE) {
            input.put(i, (rgb[3 * i].toInt() and 0xFF).toFloat())
            input.put(PLANE + i, (rgb[3 * i + 1].toInt() and 0xFF).toFloat())
            input.put(2 * PLANE + i, (rgb[3 * i + 2].toInt() and 0xFF).toFloat())
        }
        OnnxTensor.createTensor(environment, input, longArrayOf(1, 3, SIDE.toLong(), SIDE.toLong())).use { tensor ->
            session!!.run(mapOf("rgb" to tensor)).use { output ->
                @Suppress("UNCHECKED_CAST")
                return (output[0].value as Array<FloatArray>)[0]
            }
        }
    }
}
