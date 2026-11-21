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
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.BinaryCodec
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
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
    private var readerWake: ParcelFileDescriptor? = null
    private var stopping = false
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
        if (stopping) return START_NOT_STICKY
        if (engine != null) return START_STICKY
        ProtectionState.set("starting")
        try {
            startForeground(201, notification("Starting local DNS protection"))
            main.postDelayed(startupTimeout, 30000)
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
                        "ready" -> { if (!stopping && !running) establishTunnel(); result.success(null) }
                        "fatal" -> { result.success(null); fail(call.arguments.toString()) }
                        "snapshot" -> {
                            if (!stopping) {
                                ProtectionState.snapshot = JSONObject(call.arguments as String)
                                ProtectionState.emit()
                            }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("SERVICE", e.message, null); fail(e.message ?: "VPN error") }
            }
            flutter.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "package:zowy_adblocker/main.dart", "vpnMain"))
        } catch (e: Exception) {
            fail(e.message ?: "Cannot start DNS engine")
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    private fun establishTunnel() {
        val config = JSONObject(readConfiguration() ?: error("Configure protection first"))
        val builder = Builder().setSession("Zowy • local DNS")
            .addAddress("10.111.0.2", 32).addAddress("fd00:111::2", 128)
            .addDnsServer("10.111.0.1").addDnsServer("fd00:111::1")
            .addRoute("10.111.0.1", 32).addRoute("fd00:111::1", 128)
            .setMtu(1500).setBlocking(false).setMetered(false)
        builder.addDisallowedApplication(packageName)
        val excluded = config.optJSONArray("excludedApps")
        for (i in 0 until (excluded?.length() ?: 0)) {
            val name = excluded!!.getString(i)
            if (name != packageName) {
                try { builder.addDisallowedApplication(name) }
                catch (_: android.content.pm.PackageManager.NameNotFoundException) { /* App uninstalled since configuration. */ }
            }
        }
        val device = builder.establish() ?: error("VPN permission was revoked")
        tunnel = device
        val fd = device.fileDescriptor
        val packets = BasicMessageChannel(engine!!.dartExecutor.binaryMessenger, "dev.zowy/packets", BinaryCodec.INSTANCE)
        val (wakeRead, wakeWrite) = ParcelFileDescriptor.createPipe()
        readerWake = wakeWrite
        running = true
        packets.setMessageHandler { packet, reply ->
            writePacket(packet)
            reply.reply(null)
        }
        reader = thread(name = "zowy-tun") {
            wakeRead.use {
                val buffer = ByteArray(65535)
                val readable = OsConstants.POLLIN.toShort()
                val tunPoll = StructPollfd().apply { this.fd = fd; events = readable }
                val stopPoll = StructPollfd().apply { this.fd = wakeRead.fileDescriptor; events = readable }
                val poll = arrayOf(tunPoll, stopPoll)
                try {
                    while (running) {
                        Os.poll(poll, -1)
                        if (!running || stopPoll.revents.toInt() != 0) break
                        if (tunPoll.revents != readable) error("VPN tunnel closed unexpectedly")
                        val n = try { Os.read(fd, buffer, 0, buffer.size) }
                        catch (e: ErrnoException) {
                            if (e.errno == OsConstants.EAGAIN) continue
                            throw e
                        }
                        if (n <= 0) error("VPN tunnel closed unexpectedly")
                        slots.acquire()
                        val packet = ByteBuffer.allocateDirect(n).put(buffer, 0, n)
                        main.post {
                            if (!running) { slots.release(); return@post }
                            packets.send(packet) { reply ->
                                try { writePacket(reply) }
                                finally { slots.release() }
                            }
                        }
                    }
                } catch (e: Exception) {
                    if (running) main.post { if (running) fail(e.message ?: "TUN read failed") }
                }
            }
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
    private fun writePacket(packet: ByteBuffer?) {
        val fd = tunnel?.fileDescriptor ?: return
        if (!running || packet == null) return
        try {
            Os.write(fd, packet)
        } catch (e: ErrnoException) {
            // If Android's receive queue is full, drop the reply so DNS can retry.
            if (e.errno != OsConstants.EAGAIN) fail(e.message ?: "TUN write failed")
        }
    }

    fun command(name: String) { if (!stopping) channel?.invokeMethod(name, null) }

    private fun closeTunnel() {
        running = false
        main.removeCallbacks(startupTimeout)
        // Closing the pipe's writer wakes the idle reader without periodic polling.
        readerWake?.let { runCatching { it.close() } }
        readerWake = null
        tunnel?.let { runCatching { it.close() } }
        tunnel = null
        reader?.interrupt()
        reader = null
    }

    private fun finishProtection(status: String, message: String? = null) {
        if (stopping) return
        stopping = true
        closeTunnel()
        ProtectionState.snapshot.put("logs", org.json.JSONArray())
        ProtectionState.set(status, message)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun fail(message: String) = finishProtection("error", message)
    fun stopProtection() = finishProtection("stopped")
    override fun onRevoke() {
        main.post { finishProtection("stopped", "Android revoked VPN permission or another VPN replaced Zowy") }
    }

    override fun onDestroy() {
        val stoppedExplicitly = stopping
        stopping = true
        closeTunnel()
        if (watchingNetwork) {
            try { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(networkCallback) } catch (_: Exception) {}
            watchingNetwork = false
        }
        channel?.invokeMethod("shutdown", null)
        channel?.setMethodCallHandler(null)
        channel = null
        try {
            engine?.destroy()
        } finally {
            engine = null
            instance = null
            if (!stoppedExplicitly) {
                ProtectionState.snapshot.put("logs", org.json.JSONArray())
                ProtectionState.set("stopped")
            }
            stopForeground(STOP_FOREGROUND_REMOVE)
            super.onDestroy()
        }
    }
}
