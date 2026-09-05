package com.rcloneandroid.rclone_android

import android.app.Application
import com.topjohnwu.superuser.Shell

class RcloneApp : Application() {
    override fun onCreate() {
        super.onCreate()
        instance = this
        Shell.enableVerboseLogging = false
        Shell.setDefaultBuilder(
            Shell.Builder.create()
                .setFlags(Shell.FLAG_MOUNT_MASTER)
                .setTimeout(30),
        )
    }

    companion object {
        lateinit var instance: RcloneApp
            private set
    }
}
