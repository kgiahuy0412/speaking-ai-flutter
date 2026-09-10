package com.innotrik.aispeaking

import android.app.Application

class HomiApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        HomiAndroidRuntime.initialize(this)
    }
}
