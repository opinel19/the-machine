package com.emirozkunduz.person_of_interest

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    companion object {
        /** What an app shortcut asked for (`talk`, `number`); Dart takes it. */
        @Volatile
        var launchAction: String? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        launchAction = intent?.getStringExtra("poi_action") ?: launchAction
        super.onCreate(savedInstanceState)
        // A surveillance feed should not go dark while someone is watching it.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        launchAction = intent.getStringExtra("poi_action") ?: launchAction
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(FaceEmbedderPlugin())
        flutterEngine.plugins.add(MachineNativePlugin())
        flutterEngine.plugins.add(HumanDetectorPlugin())
    }
}
