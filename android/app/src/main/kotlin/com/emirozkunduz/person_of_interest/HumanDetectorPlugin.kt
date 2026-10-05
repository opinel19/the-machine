package com.emirozkunduz.person_of_interest

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Finds people in camera frames for Dart, facing the camera or not, with
 * EfficientDet-Lite0 (COCO) on LiteRT. iOS uses Vision instead.
 *
 * `detect` takes the frame letterboxed into a 320x320 RGBA square and
 * returns a flat DoubleArray of `left, top, right, bottom, score` per
 * person, as fractions of that square. Calls run on a background task queue.
 */
class HumanDetectorPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private companion object {
        const val SIDE = 320
        const val MAX_DETECTIONS = 25
        const val PERSON = 0
        const val MIN_SCORE = 0.3f
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var interpreter: Interpreter? = null
    private val input = ByteBuffer.allocateDirect(SIDE * SIDE * 3).order(ByteOrder.nativeOrder())

    // The model's own post-processing: boxes (top, left, bottom, right),
    // classes, scores and how many there are.
    private val boxes = Array(1) { Array(MAX_DETECTIONS) { FloatArray(4) } }
    private val classes = Array(1) { FloatArray(MAX_DETECTIONS) }
    private val scores = Array(1) { FloatArray(MAX_DETECTIONS) }
    private val count = FloatArray(1)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        val queue = binding.binaryMessenger.makeBackgroundTaskQueue()
        channel = MethodChannel(binding.binaryMessenger, "poi/humans", StandardMethodCodec.INSTANCE, queue)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        synchronized(this) {
            interpreter?.close()
            interpreter = null
        }
    }

    @Synchronized
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "detect") {
            result.notImplemented()
            return
        }
        val rgba = call.arguments as? ByteArray
        if (rgba == null || rgba.size != SIDE * SIDE * 4) {
            result.error("bad_input", "expected a ${SIDE}x$SIDE RGBA square", null)
            return
        }
        try {
            result.success(detect(rgba))
        } catch (e: Exception) {
            result.error("detector", e.message, null)
        }
    }

    private fun detect(rgba: ByteArray): DoubleArray {
        val model = interpreter ?: load()
        input.rewind()
        for (i in 0 until SIDE * SIDE) {
            input.put(rgba[i * 4])
            input.put(rgba[i * 4 + 1])
            input.put(rgba[i * 4 + 2])
        }
        input.rewind()
        model.runForMultipleInputsOutputs(arrayOf(input), mapOf(0 to boxes, 1 to classes, 2 to scores, 3 to count))
        val people = ArrayList<Double>()
        for (i in 0 until minOf(count[0].toInt(), MAX_DETECTIONS)) {
            if (classes[0][i].toInt() != PERSON || scores[0][i] < MIN_SCORE) continue
            val (top, left, bottom, right) = boxes[0][i]
            people += listOf(left, top, right, bottom, scores[0][i]).map { it.toDouble() }
        }
        return people.toDoubleArray()
    }

    private fun load(): Interpreter {
        val bytes = context.assets.open("PersonDetector.tflite").use { it.readBytes() }
        val model = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
        model.put(bytes).rewind()
        return Interpreter(model, Interpreter.Options().setNumThreads(2)).also { interpreter = it }
    }
}
