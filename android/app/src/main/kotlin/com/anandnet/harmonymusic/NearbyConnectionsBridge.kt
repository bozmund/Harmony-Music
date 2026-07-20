package com.anandnet.harmonymusic

import android.content.Context
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import android.util.Base64
import android.bluetooth.BluetoothManager
import android.net.wifi.WifiManager
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.NetworkInterface

/** Android-only, encrypted Nearby Connections bridge for Listen Together. */
class NearbyConnectionsBridge(private val context: Context) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private val client = Nearby.getConnectionsClient(context)
    private var sink: EventChannel.EventSink? = null
    private var radioReceiverRegistered = false
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private val pending = mutableSetOf<String>()
    private val endpointNames = mutableMapOf<String, String>()
    private val discoveredSessions = mutableMapOf<String, String>()
    // Keep discovery compatible between debug/profile/release builds. Their
    // Android application IDs have different suffixes, so context.packageName
    // would make otherwise compatible phones invisible to each other.
    private val serviceId = LISTEN_TOGETHER_SERVICE_ID

    companion object {
        internal const val LISTEN_TOGETHER_SERVICE_ID =
            "com.anandnet.harmonymusic.listen_together"
        private val STRATEGY = Strategy.P2P_STAR

        internal fun advertisingOptions() = AdvertisingOptions.Builder()
            .setStrategy(STRATEGY)
            .setLowPower(true)
            .setConnectionType(ConnectionType.NON_DISRUPTIVE)
            .build()
        internal fun discoveryOptions() = DiscoveryOptions.Builder()
            .setStrategy(STRATEGY)
            .setLowPower(true)
            .build()
        internal fun connectionOptions() = ConnectionOptions.Builder()
            .setLowPower(true)
            .setConnectionType(ConnectionType.NON_DISRUPTIVE)
            .build()

        internal fun isLocalWifiInterface(
            name: String,
            isUp: Boolean,
            isLoopback: Boolean,
            hasSiteLocalIpv4: Boolean,
        ): Boolean {
            if (!isUp || isLoopback || !hasSiteLocalIpv4) return false
            val normalized = name.lowercase()
            return normalized.startsWith("wlan") ||
                normalized.startsWith("swlan") ||
                normalized.startsWith("ap") ||
                normalized.startsWith("wifi")
        }
    }

    fun attach(messenger: io.flutter.plugin.common.BinaryMessenger) {
        methodChannel = MethodChannel(messenger, "harmonymusic/nearby_connections")
        eventChannel = EventChannel(messenger, "harmonymusic/nearby_connections/events")
        methodChannel?.setMethodCallHandler(this)
        eventChannel?.setStreamHandler(this)
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (!radioReceiverRegistered) {
            ContextCompat.registerReceiver(
                context,
                radioReceiver,
                IntentFilter().apply {
                    addAction(android.bluetooth.BluetoothAdapter.ACTION_STATE_CHANGED)
                    addAction(WifiManager.WIFI_STATE_CHANGED_ACTION)
                },
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            radioReceiverRegistered = true
        }
        event("radioState", radioState())
    }
    override fun onCancel(arguments: Any?) {
        unregisterRadioReceiver()
        sink = null
    }

    /** Releases the Activity-owned receiver and Flutter handlers. */
    fun dispose() {
        sink = null
        unregisterRadioReceiver()
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
    }

    private fun unregisterRadioReceiver() {
        if (!radioReceiverRegistered) return
        try {
            context.unregisterReceiver(radioReceiver)
        } catch (_: IllegalArgumentException) {
            // Android may already have removed the receiver while the Flutter
            // event stream is being torn down. Either way it is no longer live.
        } finally {
            radioReceiverRegistered = false
        }
    }
    private fun event(type: String, values: Map<String, Any?> = emptyMap()) { sink?.success(values + mapOf("type" to type)) }
    private val radioReceiver = object : BroadcastReceiver() {
        override fun onReceive(receiverContext: Context?, intent: Intent?) {
            event("radioState", radioState())
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "advertise" -> {
                if (!ensureAvailable(result)) return
                val name = call.argument<String>("name") ?: "Harmony"
                val sessionId = call.argument<String>("sessionId") ?: ""
                startService()
                client.startAdvertising("$name|$sessionId", serviceId, lifecycle, advertisingOptions())
                    .addOnSuccessListener { result.success(null) }.addOnFailureListener { fail(result, it) }
            }
            "discover" -> { if (!ensureAvailable(result)) return; client.startDiscovery(serviceId, discovery, discoveryOptions())
                .addOnSuccessListener { result.success(null) }.addOnFailureListener { fail(result, it) }
            }
            "connect" -> { if (!ensureAvailable(result)) return; startService(); client.requestConnection(call.argument<String>("name") ?: "Harmony", call.argument<String>("endpointId") ?: "", lifecycle, connectionOptions())
                .addOnSuccessListener { result.success(null) }.addOnFailureListener { fail(result, it) }
            }
            "getRadioState" -> result.success(radioState())
            "confirm" -> { val id = call.argument<String>("endpointId") ?: ""; val task = if (call.argument<Boolean>("accept") == true) client.acceptConnection(id, payload) else client.rejectConnection(id); task.addOnSuccessListener { pending.remove(id); result.success(null) }.addOnFailureListener { fail(result, it) } }
            "send" -> { val id = call.argument<String>("endpointId") ?: ""; val body = call.argument<String>("payload") ?: ""; client.sendPayload(id, Payload.fromBytes(Base64.decode(body, Base64.NO_WRAP))).addOnSuccessListener { result.success(null) }.addOnFailureListener { fail(result, it) } }
            "stop" -> { client.stopAdvertising(); client.stopDiscovery(); client.stopAllEndpoints(); pending.clear(); endpointNames.clear(); discoveredSessions.clear(); context.stopService(Intent(context, ListenTogetherService::class.java)); result.success(null) }
            else -> result.notImplemented()
        }
    }
    private fun radioState(): Map<String, Boolean> {
        val bluetooth = context.getSystemService(BluetoothManager::class.java)?.adapter
        val wifi = context.applicationContext.getSystemService(WifiManager::class.java)
        return mapOf(
            "bluetoothEnabled" to (bluetooth?.isEnabled == true),
            // Some OEMs disable station mode while the phone is hosting a
            // hotspot. The local Wi-Fi interface is still usable by LAN/mDNS.
            "wifiEnabled" to (wifi?.isWifiEnabled == true || hasActiveLocalWifiInterface()),
            "playServicesAvailable" to (GoogleApiAvailability.getInstance()
                .isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS),
        )
    }
    private fun hasActiveLocalWifiInterface(): Boolean {
        return try {
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return false
            while (interfaces.hasMoreElements()) {
                val item = interfaces.nextElement()
                val addresses = item.inetAddresses
                var hasSiteLocalIpv4 = false
                while (addresses.hasMoreElements()) {
                    val address = addresses.nextElement()
                    if (address is Inet4Address && address.isSiteLocalAddress) {
                        hasSiteLocalIpv4 = true
                        break
                    }
                }
                if (isLocalWifiInterface(
                        item.name.orEmpty(),
                        item.isUp,
                        item.isLoopback,
                        hasSiteLocalIpv4,
                    )
                ) return true
            }
            false
        } catch (_: Exception) {
            false
        }
    }
    private fun ensureAvailable(result: MethodChannel.Result): Boolean {
        if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) != ConnectionResult.SUCCESS) {
            result.error("PLAY_SERVICES_UNAVAILABLE", "Google Play services is unavailable", null); return false
        }
        val bluetooth = context.getSystemService(BluetoothManager::class.java)?.adapter
        if (bluetooth == null || !bluetooth.isEnabled) {
            result.error("BLUETOOTH_DISABLED", "Bluetooth is disabled", null); return false
        }
        return true
    }
    private fun startService() { ContextCompat.startForegroundService(context, Intent(context, ListenTogetherService::class.java)) }
    private fun fail(result: MethodChannel.Result, error: Exception) {
        val apiError = error as? ApiException
        val statusCode = apiError?.statusCode
        val code = statusCode?.let { "NEARBY_$it" } ?: "NEARBY_ERROR"
        val message = error.message ?: "Nearby unavailable"
        event("error", mapOf("code" to code, "message" to message))
        result.error(code, message, statusCode)
    }
    private val discovery = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(id: String, info: DiscoveredEndpointInfo) { val parts = info.endpointName.split("|", limit = 2); val sessionId = parts.getOrNull(1) ?: id; endpointNames[id] = parts[0]; discoveredSessions[id] = sessionId; event("endpointFound", mapOf("endpointId" to id, "name" to parts[0], "sessionId" to sessionId)) }
        override fun onEndpointLost(id: String) { event("endpointLost", mapOf("endpointId" to id, "sessionId" to (discoveredSessions.remove(id) ?: id))); endpointNames.remove(id) }
    }
    private val lifecycle = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(id: String, info: ConnectionInfo) { pending.add(id); endpointNames[id] = info.endpointName.substringBefore('|'); event("connectionCode", mapOf("endpointId" to id, "name" to endpointNames[id], "code" to info.authenticationToken)) }
        override fun onConnectionResult(id: String, resolution: ConnectionResolution) {
            pending.remove(id)
            val statusCode = resolution.status.statusCode
            if (statusCode == ConnectionsStatusCodes.STATUS_OK) {
                event("connected", mapOf("endpointId" to id, "name" to (endpointNames[id] ?: "Device")))
            } else {
                event("disconnected", mapOf("endpointId" to id, "code" to "NEARBY_$statusCode"))
                endpointNames.remove(id)
            }
        }
        override fun onDisconnected(id: String) { pending.remove(id); event("disconnected", mapOf("endpointId" to id)); endpointNames.remove(id) }
    }
    private val payload = object : PayloadCallback() {
        override fun onPayloadReceived(id: String, value: Payload) { if (value.type == Payload.Type.BYTES) event("payload", mapOf("endpointId" to id, "payload" to Base64.encodeToString(value.asBytes(), Base64.NO_WRAP))) }
        override fun onPayloadTransferUpdate(id: String, update: PayloadTransferUpdate) {}
    }
}
