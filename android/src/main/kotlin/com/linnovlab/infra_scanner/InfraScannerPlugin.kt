package com.linnovlab.infra_scanner

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.device.ScanDevice // <-- classe exposée par ton JAR
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Plugin InfraScanner : wrap direct de android.device.ScanDevice + flux EventChannel */
class InfraScannerPlugin :
        FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private var context: Context? = null
    private var activity: Activity? = null

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var scanDevice: ScanDevice? = null

    private val METHOD_CHANNEL = "com.linnovlab/infra_scanner"
    private val EVENT_CHANNEL = "com.linnovlab/infra_scanner/scanStream"

    /** Action broadcast utilisée par le service de scan du PDA */
    private val SCAN_ACTION = "scan.rcv.message"

    /** Récepteur des résultats de scan (mode Out=Broadcast) */
    private val scanReceiver =
            object : BroadcastReceiver() {
                override fun onReceive(c: Context?, intent: Intent?) {
                    if (intent?.action != SCAN_ACTION) return
                    try {
                        // Extras usuels: "barocode" (byte[]), "length" (int), "barcodeType"
                        // (String), "aimid" (String)
                        val rawBytes = intent.getByteArrayExtra("barocode") ?: ByteArray(0)
                        val length =
                                intent.getIntExtra("length", rawBytes.size)
                                        .coerceAtMost(rawBytes.size)
                        val barcodeType = intent.getStringExtra("barcodeType") ?: ""
                        val aimId = intent.getStringExtra("aimid") ?: ""
                        val code = bytesToString(rawBytes, length)

                        val map =
                                mapOf(
                                        "code" to code,
                                        "length" to length,
                                        "barcodeType" to barcodeType,
                                        "aimId" to aimId,
                                        "raw" to rawBytes
                                )
                        eventSink?.success(map)
                    } catch (t: Throwable) {
                        eventSink?.error("RECEIVER_ERROR", t.message, null)
                    }
                }
            }

    private fun bytesToString(bytes: ByteArray, length: Int): String {
        if (length <= 0) return ""
        // Les scanners renvoient généralement ASCII/UTF-8. On tente UTF-8, sinon fallback basique.
        return try {
            String(bytes, 0, length, Charsets.UTF_8)
        } catch (_: Throwable) {
            String(bytes, 0, length)
        }
    }

    // ---------------- FlutterPlugin ----------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        channel.setMethodCallHandler(this)

        events = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        context = null
    }

    // ---------------- ActivityAware ----------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        // Instancie le SDK (nécessite l’APK/Service du constructeur présent sur le PDA)
        scanDevice =
                try {
                    ScanDevice()
                } catch (_: Throwable) {
                    null
                }

        // Tente de forcer le mode broadcast dès l’attache
        runCatching { scanDevice?.setOutScanMode(0) }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        if (scanDevice == null) {
            scanDevice = runCatching { ScanDevice() }.getOrNull()
            runCatching { scanDevice?.setOutScanMode(0) }
        }
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    // ---------------- MethodChannel ----------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val dev = scanDevice
        if (dev == null) {
            result.error("NO_SDK", "ScanDevice introuvable dans le JAR / service non présent", null)
            return
        }

        when (call.method) {
            "isScanOpened" -> {
                // Certaines versions exposent isScanOpened(); si non dispo, on renvoie false sans
                // planter.
                val opened =
                        runCatching { dev.isScanOpened }.getOrElse {
                            runCatching { dev.isScanOpened() }.getOrDefault(false)
                        }
                result.success(opened)
            }
            "openScan" -> result.success(runCatching { dev.openScan() }.getOrDefault(false))
            "closeScan" -> result.success(runCatching { dev.closeScan() }.getOrDefault(false))
            "startScan" -> result.success(runCatching { dev.startScan() }.getOrDefault(false))
            "stopScan" -> result.success(runCatching { dev.stopScan() }.getOrDefault(false))
            "resetScan" -> result.success(runCatching { dev.resetScan() }.getOrDefault(false))
            "setContinuous" -> {
                val on = call.argument<Boolean>("on") ?: false
                runCatching { dev.setScanLaserMode(if (on) 4 else 8) }
                result.success(null)
            }
            "setOutScanMode" -> {
                val mode = call.argument<Int>("mode") ?: 0 // 0=broadcast, 1=edit box, 2=keyboard
                val ok = runCatching { dev.setOutScanMode(mode) }.getOrDefault(true)
                result.success(ok)
            }
            "getOutScanMode" -> {
                val mode =
                        runCatching { dev.outScanMode }.getOrElse {
                            runCatching { dev.getOutScanMode() }.getOrDefault(0)
                        }
                result.success(mode)
            }
            else -> result.notImplemented()
        }
    }

    // ---------------- EventChannel ----------------

    override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
        val ctx = context ?: return
        val filter = IntentFilter(SCAN_ACTION)

        // API 33+: il faut préciser NOT_EXPORTED/EXPORTED ; en dessous, on utilise la vieille
        // signature
        if (Build.VERSION.SDK_INT >= 33) {
            ctx.registerReceiver(scanReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION") ctx.registerReceiver(scanReceiver, filter)
        }
    }

    override fun onCancel(args: Any?) {
        val ctx = context ?: return
        eventSink = null
        runCatching { ctx.unregisterReceiver(scanReceiver) }
    }
}
