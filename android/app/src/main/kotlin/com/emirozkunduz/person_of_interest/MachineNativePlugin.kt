package com.emirozkunduz.person_of_interest

import android.Manifest
import android.app.Activity
import android.app.KeyguardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.Locale
import kotlin.random.Random

/**
 * Native services for Dart (`poi/native`): the voice and listening, sounds,
 * saving to the gallery and device-owner authentication. In-app screen
 * recording is not offered on Android (the system recorder does it).
 *
 * Speech events go back to Dart as `onSpeech` calls: `level`, `partial` and
 * `final` while listening, `spoken` when the voice falls silent.
 */
class MachineNativePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {
    private companion object {
        const val AUTH_REQUEST = 0x504f49
        const val MIC_REQUEST = 0x504f4a
    }

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activity: ActivityPluginBinding? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val pendingSpeech = mutableListOf<Pair<List<String>, Boolean>>()
    private var player: MediaPlayer? = null
    private var pendingAuth: MethodChannel.Result? = null
    private var lastVoice: String? = null
    private var utterance = 0

    // Utterances queued or being spoken.
    private val speaking = mutableSetOf<String>()
    private var recognizer: SpeechRecognizer? = null
    private var heard = ""
    private var pendingListen: Pair<String, MethodChannel.Result>? = null
    private val main = Handler(Looper.getMainLooper())

    private val progress = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {}

        override fun onDone(utteranceId: String?) = utteranceEnded(utteranceId)

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String?) = utteranceEnded(utteranceId)

        override fun onStop(utteranceId: String?, interrupted: Boolean) = utteranceEnded(utteranceId)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "poi/native")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        tts?.shutdown()
        player?.release()
        recognizer?.destroy()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity?.removeActivityResultListener(this)
        activity?.removeRequestPermissionsResultListener(this)
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "speak" -> {
                val words = call.argument<List<String>>("words") ?: emptyList()
                speak(words, call.argument<Boolean>("cutUp") ?: true)
                result.success(null)
            }
            "stopSpeaking" -> {
                stopSpeaking()
                result.success(null)
            }
            "listen" -> listen(call.arguments as? String ?: "en-US", result)
            "stopListening" -> {
                stopListening()
                result.success(null)
            }
            "playSound" -> {
                playSound(call.arguments as? String)
                result.success(null)
            }
            "stopSound" -> {
                player?.release()
                player = null
                result.success(null)
            }
            "saveImage" -> result.success(saveImage(call.arguments as? ByteArray))
            "startRecording", "stopRecording" -> result.success(false)
            "takeLaunchAction" -> {
                result.success(MainActivity.launchAction)
                MainActivity.launchAction = null
            }
            "authenticate" -> authenticate(call.arguments as? String ?: "Unlock", result)
            else -> result.notImplemented()
        }
    }

    // Speech

    private fun speak(words: List<String>, cutUp: Boolean) {
        if (words.isEmpty() || recognizer != null) return
        val engine = tts
        if (engine == null) {
            pendingSpeech.add(words to cutUp)
            tts = TextToSpeech(context) { status ->
                ttsReady = status == TextToSpeech.SUCCESS
                if (ttsReady) {
                    pendingSpeech.forEach { (w, c) -> speakNow(w, c) }
                }
                pendingSpeech.clear()
            }.apply { setOnUtteranceProgressListener(progress) }
            return
        }
        if (!ttsReady) {
            pendingSpeech.add(words to cutUp)
            return
        }
        speakNow(words, cutUp)
    }

    private fun speakNow(words: List<String>, cutUp: Boolean) {
        val engine = tts ?: return
        if (!cutUp) {
            engine.language = Locale.UK
            engine.setPitch(0.9f)
            engine.setSpeechRate(0.95f)
            engine.speak(words.joinToString(" "), TextToSpeech.QUEUE_ADD, null, track("poi-${utterance++}"))
            return
        }
        // Every word in a different voice, like the Machine talking through
        // snippets of recorded people.
        val voices: List<Voice> = engine.voices.orEmpty().filter {
            it.locale.language == "en" && !it.isNetworkConnectionRequired &&
                !it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
        }
        for (word in words) {
            var voice = voices.randomOrNull()
            if (voices.size > 1) {
                while (voice?.name == lastVoice) voice = voices.random()
            }
            lastVoice = voice?.name
            if (voice != null) engine.voice = voice
            engine.setPitch(Random.nextDouble(0.85, 1.15).toFloat())
            engine.setSpeechRate(Random.nextDouble(0.9, 1.1).toFloat())
            engine.speak(word, TextToSpeech.QUEUE_ADD, null, track("poi-${utterance++}"))
        }
    }

    private fun track(id: String): String {
        synchronized(speaking) { speaking.add(id) }
        return id
    }

    private fun utteranceEnded(id: String?) {
        val silent = synchronized(speaking) { speaking.remove(id) && speaking.isEmpty() }
        if (silent) sendSpeech("spoken")
    }

    private fun stopSpeaking() {
        tts?.stop()
        val wasSpeaking = synchronized(speaking) {
            val any = speaking.isNotEmpty()
            speaking.clear()
            any
        }
        if (wasSpeaking) sendSpeech("spoken")
    }

    // Listening

    private fun listen(locale: String, result: MethodChannel.Result) {
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            startListening(locale, result)
            return
        }
        val host = activity?.activity
        if (host == null) {
            result.error("denied", "No activity to ask for the microphone", null)
            return
        }
        pendingListen?.second?.error("denied", "Superseded", null)
        pendingListen = locale to result
        host.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != MIC_REQUEST) return false
        val (locale, result) = pendingListen ?: return true
        pendingListen = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startListening(locale, result)
        } else {
            result.error("denied", "Microphone access denied", null)
        }
        return true
    }

    private fun startListening(locale: String, result: MethodChannel.Result) {
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            result.error("unavailable", "No speech recognition service on this device", null)
            return
        }
        stopSpeaking()
        recognizer?.destroy()
        heard = ""
        val listener = SpeechRecognizer.createSpeechRecognizer(context)
        recognizer = listener
        listener.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}

            override fun onBeginningOfSpeech() {}

            override fun onRmsChanged(rmsdB: Float) {
                if (recognizer === listener) sendSpeech("level", level = ((rmsdB + 2f) / 12f).coerceIn(0f, 1f).toDouble())
            }

            override fun onBufferReceived(buffer: ByteArray?) {}

            override fun onEndOfSpeech() {}

            override fun onError(error: Int) = finishListening(listener)

            override fun onResults(results: Bundle?) {
                results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.let { heard = it }
                finishListening(listener)
            }

            override fun onPartialResults(partialResults: Bundle?) {
                val text = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                if (recognizer === listener && !text.isNullOrBlank()) {
                    heard = text
                    sendSpeech("partial", text = text)
                }
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        listener.startListening(
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            },
        )
        result.success(true)
    }

    // Stops listening; the results (or an error) follow and end it.
    private fun stopListening() {
        val listener = recognizer
        if (listener == null) sendSpeech("final") else listener.stopListening()
    }

    private fun finishListening(listener: SpeechRecognizer) {
        if (recognizer !== listener) return
        recognizer = null
        listener.destroy()
        sendSpeech("final", text = heard)
        heard = ""
    }

    private fun sendSpeech(type: String, text: String = "", level: Double = 0.0) {
        val event = mapOf("type" to type, "text" to text, "level" to level)
        if (Looper.myLooper() == Looper.getMainLooper()) {
            channel.invokeMethod("onSpeech", event)
        } else {
            main.post { channel.invokeMethod("onSpeech", event) }
        }
    }

    // Sound

    private fun playSound(asset: String?) {
        if (asset == null) return
        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
        // Flutter assets may be compressed inside the APK; play a cached copy.
        val file = File(context.cacheDir, asset.substringAfterLast('/'))
        if (!file.exists()) {
            context.assets.open(key).use { input -> file.outputStream().use { input.copyTo(it) } }
        }
        player?.release()
        player = MediaPlayer().apply {
            setDataSource(file.path)
            setOnCompletionListener { it.release(); if (player === it) player = null }
            prepare()
            start()
        }
    }

    // Gallery

    private fun saveImage(png: ByteArray?): Boolean {
        if (png == null) return false
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "machine-${System.currentTimeMillis()}.png")
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/The Machine")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return false
        return try {
            resolver.openOutputStream(uri)?.use { it.write(png) } ?: return false
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            true
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            false
        }
    }

    // Authentication

    @Suppress("DEPRECATION")
    private fun authenticate(reason: String, result: MethodChannel.Result) {
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val host: Activity? = activity?.activity
        // Without a screen lock there is no owner to check, and refusing would
        // lock the user out of their own settings.
        if (!keyguard.isDeviceSecure || host == null) {
            result.success(true)
            return
        }
        val intent: Intent? = keyguard.createConfirmDeviceCredentialIntent("The Machine", reason)
        if (intent == null) {
            result.success(true)
            return
        }
        pendingAuth = result
        host.startActivityForResult(intent, AUTH_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != AUTH_REQUEST) return false
        pendingAuth?.success(resultCode == Activity.RESULT_OK)
        pendingAuth = null
        return true
    }
}
