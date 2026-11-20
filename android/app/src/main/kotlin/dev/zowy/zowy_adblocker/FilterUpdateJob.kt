package dev.zowy.zowy_adblocker

import android.app.job.JobParameters
import android.app.job.JobService
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class FilterUpdateJob : JobService() {
    private var engine: FlutterEngine? = null
    private var current: JobParameters? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { finish("Filter update exceeded 10 minutes", true) }
    override fun onStartJob(params: JobParameters): Boolean {
        current = params
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            val flutter = FlutterEngine(this); engine = flutter
            MethodChannel(flutter.dartExecutor.binaryMessenger, "dev.zowy/runtime").setMethodCallHandler { call, result ->
                when (call.method) {
                    "loadConfig" -> result.success(readConfiguration())
                    "dataPath" -> result.success(filesDir.absolutePath)
                    "jobDone" -> { result.success(null); handler.post { finish(call.arguments.toString(), false) } }
                    else -> result.notImplemented()
                }
            }
            handler.postDelayed(timeout, 600000)
            flutter.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "package:zowy_adblocker/main.dart", "filterUpdateMain"))
            return true
        } catch (e: Exception) { finish(e.message ?: "Update startup failed", true); return false }
    }
    private fun finish(error: String, retry: Boolean) {
        preferences().edit().putString("updateError", error.ifEmpty { null }).apply()
        DnsVpnService.instance?.reload()
        current?.let { jobFinished(it, retry) }; current = null
        handler.removeCallbacks(timeout); engine?.destroy(); engine = null
    }
    override fun onStopJob(params: JobParameters): Boolean {
        current = null; handler.removeCallbacks(timeout); engine?.destroy(); engine = null
        return true
    }
}
