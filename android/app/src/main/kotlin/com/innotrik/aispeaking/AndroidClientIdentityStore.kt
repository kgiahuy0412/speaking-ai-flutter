package com.innotrik.aispeaking

import android.content.Context
import java.util.UUID

/**
 * Stores HOMI's public installation id separately from the Android hardware
 * identifier.  The backend can ask an installation to rotate this id after a
 * stale credential conflict; ANDROID_ID cannot support that recovery flow.
 */
class AndroidClientIdentityStore(context: Context) {
    private val preferences = context.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    @Synchronized
    fun getOrCreate(): String {
        val existing = preferences.getString(CLIENT_ID_KEY, null)?.trim()
        if (!existing.isNullOrEmpty()) return existing

        val clientId = createClientId()
        check(preferences.edit().putString(CLIENT_ID_KEY, clientId).commit()) {
            "Không thể lưu mã cài đặt HOMI."
        }
        return clientId
    }

    @Synchronized
    fun reset(): String {
        val clientId = createClientId()
        check(preferences.edit().putString(CLIENT_ID_KEY, clientId).commit()) {
            "Không thể làm mới mã cài đặt HOMI."
        }
        return clientId
    }

    private fun createClientId(): String = "android_${UUID.randomUUID()}"

    private companion object {
        const val PREFERENCES_NAME = "homi_client_identity"
        const val CLIENT_ID_KEY = "client_id"
    }
}
