package dev.zowy.zowy_adblocker

import android.app.Activity
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import rikka.shizuku.Shizuku
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

object ProtectionState {
    var status = "stopped"
    var error: String? = null
    var snapshot = JSONObject()
    var sink: EventChannel.EventSink? = null
    fun json(): String = JSONObject(snapshot.toString()).apply {
        put("status", status); put("serviceError", error ?: JSONObject.NULL)
    }.toString()
    fun emit(capabilitiesChanged: Boolean = false) {
        sink?.success(if (capabilitiesChanged) JSONObject(json()).put("capabilitiesChanged", true).toString() else json())
    }
    fun set(value: String, message: String? = null) {
        status = value; error = message; emit()
    }
}

fun Context.preferences() = getSharedPreferences("zowy", Context.MODE_PRIVATE)

fun Context.scheduleUpdates() {
    val scheduler = getSystemService(JobScheduler::class.java)
    val text = readConfiguration() ?: return
    val hours = JSONObject(text).optInt("updateHours", 24)
    if (hours == 0) { scheduler.cancel(301); return }
    if (scheduler.getPendingJob(301)?.intervalMillis == hours * 3600000L) return
    scheduler.cancel(301)
    scheduler.schedule(JobInfo.Builder(301, ComponentName(this, FilterUpdateJob::class.java))
        .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
        .setRequiresBatteryNotLow(true)
        .setPersisted(true)
        .setPeriodic(hours * 3600000L)
        .build())
}

class MainActivity : FlutterActivity() {
    private var pendingVpn: MethodChannel.Result? = null
    private var pendingDocument: MethodChannel.Result? = null
    private var exportText: String? = null
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val binderReceived = Shizuku.OnBinderReceivedListener { ProtectionState.emit(true) }
    private val binderDead = Shizuku.OnBinderDeadListener { ProtectionState.emit(true) }
    private val permissionResult = Shizuku.OnRequestPermissionResultListener { _, _ -> ProtectionState.emit(true) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Shizuku.addBinderReceivedListenerSticky(binderReceived)
        Shizuku.addBinderDeadListener(binderDead)
        Shizuku.addRequestPermissionResultListener(permissionResult)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.zowy/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    ProtectionState.sink = events; ProtectionState.emit()
                }
                override fun onCancel(arguments: Any?) { ProtectionState.sink = null }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.zowy/control")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "loadConfig" -> result.success(readConfiguration())
                        "dataPath" -> result.success(filesDir.absolutePath)
                        "saveConfig" -> {
                            val text = call.arguments as String
                            require(text.toByteArray().size <= 2097152)
                            require(JSONObject(text).getInt("version") == 1)
                            writeConfiguration(text)
                            if (!JSONObject(text).optBoolean("logging", false)) {
                                ProtectionState.snapshot.put("logs", org.json.JSONArray())
                                ProtectionState.emit()
                            }
                            scheduleUpdates()
                            DnsVpnService.instance?.reload()
                            result.success(null)
                        }
                        "restoreConfig" -> {
                            val backup = readConfiguration(backup = true)
                            if (backup == null) result.error("NO_BACKUP", "No previous configuration", null)
                            else result.success(backup)
                        }
                        "start" -> {
                            check(pendingVpn == null) { "VPN permission request already pending" }
                            val permission = VpnService.prepare(this)
                            if (permission != null) {
                                pendingVpn = result
                                startActivityForResult(permission, 100)
                            } else { startProtection(); result.success(null) }
                        }
                        "stop" -> {
                            DnsVpnService.instance?.stopProtection()
                            result.success(null)
                        }
                        "snapshot" -> result.success(ProtectionState.json())
                        "clearLogs", "clearCache", "resetStats" -> {
                            DnsVpnService.instance?.command(call.method)
                            if (DnsVpnService.instance == null) {
                                ProtectionState.snapshot = JSONObject(); ProtectionState.emit()
                            }
                            result.success(null)
                        }
                        "capabilities" -> result.success(capabilities())
                        "vpnSettings" -> { startActivity(Intent(Settings.ACTION_VPN_SETTINGS)); result.success(null) }
                        "privateDnsSettings" -> { startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS)); result.success(null) }
                        "shizukuPermission" -> {
                            check(Shizuku.pingBinder()) { "Start the Shizuku server first" }
                            check(!Shizuku.isPreV11()) { "Shizuku API 11+ is required" }
                            if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) Shizuku.requestPermission(101)
                            result.success(null)
                        }
                        "rootCheck" -> executor.execute {
                            try {
                                val process = ProcessBuilder("su", "-c", "id").redirectErrorStream(true).start()
                                check(process.waitFor(15, TimeUnit.SECONDS)) { process.destroyForcibly(); "Root request timed out" }
                                val output = process.inputStream.bufferedReader().use { it.readText().take(4096) }
                                check(process.exitValue() == 0 && Regex("(^|\\s)uid=0\\b").containsMatchIn(output)) { "Root not granted: $output" }
                                main.post { result.success(output) }
                            } catch (e: Exception) { main.post { result.error("ROOT", e.message, null) } }
                        }
                        "appIcon" -> executor.execute {
                            try {
                                val drawable = packageManager.getApplicationIcon(call.arguments as String)
                                val bitmap = android.graphics.Bitmap.createBitmap(96, 96, android.graphics.Bitmap.Config.ARGB_8888)
                                drawable.setBounds(0, 0, 96, 96)
                                drawable.draw(android.graphics.Canvas(bitmap))
                                val bytes = java.io.ByteArrayOutputStream().use { out ->
                                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
                                    out.toByteArray()
                                }
                                bitmap.recycle()
                                main.post { result.success(bytes) }
                            } catch (_: Exception) { main.post { result.success(null) } }
                        }
                        "applications" -> executor.execute {
                            try {
                                val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                                val apps = packageManager.queryIntentActivities(intent, 0)
                                    .distinctBy { it.activityInfo.packageName }.map { info ->
                                        mapOf("package" to info.activityInfo.packageName,
                                            "name" to info.loadLabel(packageManager).toString(),
                                            "system" to ((info.activityInfo.applicationInfo.flags and 1) != 0))
                                    }.sortedBy { it["name"].toString().lowercase() }
                                main.post { result.success(apps) }
                            } catch (e: Exception) { main.post { result.error("APPS", e.message, null) } }
                        }
                        "export" -> {
                            check(pendingDocument == null) { "A document request is pending" }
                            exportText = call.argument<String>("text")!!
                            require(exportText!!.toByteArray().size <= 33554432)
                            pendingDocument = result
                            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE); type = "text/plain"
                                putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "zowy.json")
                            }, 102)
                        }
                        "import" -> {
                            check(pendingDocument == null) { "A document request is pending" }
                            pendingDocument = result
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE); type = "*/*"
                            }, 103)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("PLATFORM", e.message, null) }
            }
    }

    private fun startProtection() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 104)
        }
        ProtectionState.set("starting")
        try { startForegroundService(Intent(this, DnsVpnService::class.java)) }
        catch (e: Exception) { ProtectionState.set("error", e.message); throw e }
    }

    private fun capabilities(): Map<String, Any?> {
        val cm = getSystemService(ConnectivityManager::class.java)
        val network = cm.activeNetwork
        val properties = cm.getLinkProperties(network)
        val shizuku = Shizuku.pingBinder()
        val granted = try { shizuku && !Shizuku.isPreV11() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED } catch (_: Exception) { false }
        val uid = try { if (granted) Shizuku.getUid() else null } catch (_: Exception) { null }
        val installed = try { packageManager.getPackageInfo("moe.shizuku.privileged.api", 0); true } catch (_: PackageManager.NameNotFoundException) { false }
        val alive = shizuku && Shizuku.pingBinder()
        return mapOf("android" to Build.VERSION.SDK_INT,
            "vpnPrepared" to (VpnService.prepare(this) == null),
            "otherVpn" to (cm.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true && DnsVpnService.instance == null),
            "privateDns" to (if (Build.VERSION.SDK_INT >= 28) properties?.isPrivateDnsActive == true else false),
            "privateDnsHost" to (if (Build.VERSION.SDK_INT >= 28) properties?.privateDnsServerName else null),
            "shizukuInstalled" to installed,
            "shizukuRunning" to alive, "shizukuGranted" to (alive && granted && uid != null),
            "shizukuUid" to (if (alive) uid else null),
            "rootBinaryPresent" to listOf("/system/bin/su", "/system/xbin/su", "/sbin/su").any { File(it).exists() },
            "rootFiltering" to false, "firewall" to false,
            "updateError" to preferences().getString("updateError", null))
    }

    @Deprecated("Android activity callback used by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 100) {
            val result = pendingVpn; pendingVpn = null
            if (resultCode == Activity.RESULT_OK) {
                try { startProtection(); result?.success(null) }
                catch (e: Exception) { result?.error("VPN", e.message, null) }
            } else { ProtectionState.set("stopped", "VPN permission denied"); result?.error("VPN_DENIED", "VPN permission denied", null) }
        }
        if (requestCode == 102 || requestCode == 103) {
            val result = pendingDocument; pendingDocument = null
            val text = exportText; exportText = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) { result?.success(null); return }
            executor.execute {
                try {
                    if (requestCode == 102) {
                        contentResolver.openOutputStream(uri, "wt")!!.use { it.write(text!!.toByteArray(Charsets.UTF_8)) }
                        main.post { result?.success(true) }
                    } else {
                        val bytes = contentResolver.openInputStream(uri)!!.use { input ->
                            val out = java.io.ByteArrayOutputStream()
                            val buffer = ByteArray(8192)
                            while (true) {
                                val n = input.read(buffer)
                                if (n < 0) break
                                check(out.size() + n <= 33554432) { "Import exceeds 32 MiB" }
                                out.write(buffer, 0, n)
                            }
                            out.toByteArray()
                        }
                        check(bytes.size <= 33554432) { "Import exceeds 32 MiB" }
                        main.post { result?.success(bytes.toString(Charsets.UTF_8)) }
                    }
                } catch (e: Exception) { main.post { result?.error("DOCUMENT", e.message, null) } }
            }
        }
    }

    override fun onDestroy() {
        Shizuku.removeBinderReceivedListener(binderReceived)
        Shizuku.removeBinderDeadListener(binderDead)
        Shizuku.removeRequestPermissionResultListener(permissionResult)
        pendingVpn?.error("CANCELLED", "Activity closed during VPN consent", null)
        pendingDocument?.error("CANCELLED", "Activity closed during document selection", null)
        pendingVpn = null; pendingDocument = null; exportText = null
        ProtectionState.sink = null
        executor.shutdown()
        super.onDestroy()
    }
}
