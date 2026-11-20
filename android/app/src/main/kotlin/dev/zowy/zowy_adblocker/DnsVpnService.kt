package dev.zowy.zowy_adblocker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryCodec
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Semaphore
import kotlin.concurrent.thread

class DnsVpnService : VpnService() {
    companion object { var instance: DnsVpnService? = null; private set }
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var tunnel: ParcelFileDescriptor? = null
    @Volatile private var running = false
    private val main = Handler(Looper.getMainLooper())
    private var reader: Thread? = null
    private var input: FileInputStream? = null
    private var output: FileOutputStream? = null
    private val slots = Semaphore(64)
    private var currentNetwork: Network? = null
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { main.post {
            if (currentNetwork != network) { currentNetwork = network; command("networkChanged") }
        } }
        override fun onLost(network: Network) { main.post {
            if (currentNetwork == network) { currentNetwork = null; command("networkChanged") }
        } }
    }
    private var watchingNetwork = false
    private val startupTimeout = Runnable {
        if (ProtectionState.status == "starting") fail("DNS engine startup timed out")
    }

    override fun onCreate() {
        super.onCreate(); instance = this
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("protection", "DNS protection", NotificationManager.IMPORTANCE_LOW))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") { stopProtection(); return START_NOT_STICKY }
        if (engine != null) return START_STICKY
        ProtectionState.set("starting")
        startForeground(201, notification("Starting local DNS protection"))
        main.postDelayed(startupTimeout, 30000)
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            val flutter = FlutterEngine(this)
            engine = flutter
            channel = MethodChannel(flutter.dartExecutor.binaryMessenger, "dev.zowy/runtime")
            channel!!.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "loadConfig" -> result.success(readConfiguration())
                        "dataPath" -> result.success(filesDir.absolutePath)
                        "ready" -> { establishTunnel(); result.success(null) }
                        "fatal" -> { result.success(null); fail(call.arguments.toString()) }
                        "snapshot" -> {
                            ProtectionState.snapshot = JSONObject(call.arguments as String)
                            ProtectionState.emit(); result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("SERVICE", e.message, null); fail(e.message ?: "VPN error") }
            }
            flutter.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "package:zowy_adblocker/main.dart", "vpnMain"))
        } catch (e: Exception) { fail(e.message ?: "Cannot start DNS engine") }
        return START_STICKY
    }

    private fun establishTunnel() {
        val config = JSONObject(readConfiguration() ?: error("Configure protection first"))
        val builder = Builder().setSession("Zowy • local DNS")
            .addAddress("10.111.0.2", 32).addAddress("fd00:111::2", 128)
            .addDnsServer("10.111.0.1").addDnsServer("fd00:111::1")
            .addRoute("10.111.0.1", 32).addRoute("fd00:111::1", 128)
            .setMtu(1500).setBlocking(true).setMetered(false)
        builder.addDisallowedApplication(packageName)
        val excluded = config.optJSONArray("excludedApps")
        for (i in 0 until (excluded?.length() ?: 0)) {
            val name = excluded!!.getString(i)
            if (name != packageName) {
                try { builder.addDisallowedApplication(name) }
                catch (_: android.content.pm.PackageManager.NameNotFoundException) { /* App uninstalled since configuration. */ }
            }
        }
        tunnel = builder.establish() ?: error("VPN permission was revoked")
        input = FileInputStream(tunnel!!.fileDescriptor)
        output = FileOutputStream(tunnel!!.fileDescriptor)
        running = true
        val packets = BasicMessageChannel(engine!!.dartExecutor.binaryMessenger, "dev.zowy/packets", BinaryCodec.INSTANCE)
        packets.setMessageHandler { packet, reply ->
            try {
                if (running && packet != null) {
                    val bytes = ByteArray(packet.remaining()); packet.get(bytes); output?.write(bytes)
                }
                reply.reply(null)
            } catch (e: Exception) { reply.reply(null); if (running) fail(e.message ?: "TCP TUN write failed") }
        }
        reader = thread(name = "zowy-tun") {
            val buffer = ByteArray(65535)
            try {
                while (running) {
                    slots.acquire()
                    val n = input!!.read(buffer)
                    if (n <= 0) { slots.release(); break }
                    val packet = ByteBuffer.allocateDirect(n).put(buffer, 0, n)
                    main.post {
                        if (!running) { slots.release(); return@post }
                        packets.send(packet) { reply ->
                            try {
                                if (running && reply != null) {
                                    val bytes = ByteArray(reply.remaining()); reply.get(bytes)
                                    output?.write(bytes)
                                }
                            } catch (e: Exception) { if (running) fail(e.message ?: "TUN write failed") }
                            finally { slots.release() }
                        }
                    }
                }
                if (running) main.post { fail("VPN tunnel closed unexpectedly") }
            } catch (e: Exception) { if (running) main.post { fail(e.message ?: "TUN read failed") } }
        }
        main.removeCallbacks(startupTimeout)
        ProtectionState.set("running")
        val connectivity = getSystemService(ConnectivityManager::class.java)
        currentNetwork = connectivity.activeNetwork
        connectivity.registerDefaultNetworkCallback(networkCallback)
        watchingNetwork = true
        getSystemService(NotificationManager::class.java).notify(201, notification("Local DNS protection is active"))
    }

    private fun notification(text: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, DnsVpnService::class.java).setAction("STOP"), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, "protection")
            .setSmallIcon(R.drawable.ic_notification).setContentTitle("Zowy Adblocker")
            .setContentText(text).setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build()).build()
    }

    fun reload() {
        // App exclusions are applied by Builder and require an explicit restart.
        channel?.invokeMethod("reload", null, object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(code: String, message: String?, details: Any?) { ProtectionState.error = message; ProtectionState.emit() }
            override fun notImplemented() {}
        })
    }
    fun command(name: String) { channel?.invokeMethod(name, null) }
    private fun fail(message: String) { ProtectionState.set("error", message); stopSelf() }
    fun stopProtection() { ProtectionState.set("stopped"); stopSelf() }
    override fun onRevoke() { ProtectionState.set("stopped", "Android revoked VPN permission or another VPN replaced Zowy"); stopSelf() }
    override fun onDestroy() {
        running = false; main.removeCallbacks(startupTimeout)
        if (watchingNetwork) {
            try { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(networkCallback) } catch (_: Exception) {}
            watchingNetwork = false
        }
        try { tunnel?.close() } catch (_: Exception) {}
        try { input?.close() } catch (_: Exception) {}
        try { output?.close() } catch (_: Exception) {}
        reader?.interrupt(); reader = null
        channel?.invokeMethod("shutdown", null)
        engine?.destroy(); engine = null; tunnel = null
        instance = null
        ProtectionState.snapshot.put("logs", org.json.JSONArray())
        if (ProtectionState.status != "error") ProtectionState.set("stopped")
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
