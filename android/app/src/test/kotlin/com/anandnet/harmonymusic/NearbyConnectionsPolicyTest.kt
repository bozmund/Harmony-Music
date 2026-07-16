package com.anandnet.harmonymusic

import com.google.android.gms.nearby.connection.Strategy
import com.google.android.gms.nearby.connection.ConnectionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NearbyConnectionsPolicyTest {
    @Test
    fun `advertising is BLE low power and uses star topology`() {
        val options = NearbyConnectionsBridge.advertisingOptions()
        assertTrue(options.lowPower)
        assertEquals(Strategy.P2P_STAR, options.strategy)
        assertEquals(ConnectionType.NON_DISRUPTIVE, options.connectionType)
    }

    @Test
    fun `discovery is BLE low power and uses star topology`() {
        val options = NearbyConnectionsBridge.discoveryOptions()
        assertTrue(options.lowPower)
        assertEquals(Strategy.P2P_STAR, options.strategy)
    }

    @Test
    fun `connection remains BLE low power`() {
        val options = NearbyConnectionsBridge.connectionOptions()
        assertTrue(options.lowPower)
        assertEquals(ConnectionType.NON_DISRUPTIVE, options.connectionType)
    }

    @Test
    fun `active OEM hotspot interfaces count as Wi-Fi LAN readiness`() {
        assertTrue(NearbyConnectionsBridge.isLocalWifiInterface("wlan0", true, false, true))
        assertTrue(NearbyConnectionsBridge.isLocalWifiInterface("swlan0", true, false, true))
        assertTrue(NearbyConnectionsBridge.isLocalWifiInterface("ap0", true, false, true))
    }

    @Test
    fun `cellular and inactive interfaces do not count as Wi-Fi LAN readiness`() {
        assertEquals(false, NearbyConnectionsBridge.isLocalWifiInterface("rmnet0", true, false, true))
        assertEquals(false, NearbyConnectionsBridge.isLocalWifiInterface("wlan0", false, false, true))
        assertEquals(false, NearbyConnectionsBridge.isLocalWifiInterface("wlan0", true, false, false))
    }
}
