package com.innotrik.aispeaking

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Locale
import java.util.concurrent.TimeUnit
import java.util.zip.ZipInputStream

data class HomiOfflineSpeechModelSpec(
    val locale: String,
    val modelId: String,
    val downloadBytes: Long,
    val runtimeMemoryBytes: Long,
    val downloadUrl: String,
    val downloadSha256: String,
) {
    val normalizedLocale: String
        get() = locale.lowercase(Locale.US)

    val workName: String
        get() = "homi.offline-speech.$normalizedLocale.$modelId"
}

/** Vosk language packs owned by the app and shared by its offline features. */
object HomiOfflineSpeechModels {
    val english =
        HomiOfflineSpeechModelSpec(
            locale = "en-US",
            modelId = "vosk-model-small-en-us-0.15",
            downloadBytes = 41_205_931L,
            runtimeMemoryBytes = 300_000_000L,
            downloadUrl =
                "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip",
            downloadSha256 =
                "30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498",
        )

    val vietnamese =
        HomiOfflineSpeechModelSpec(
            locale = "vi-VN",
            modelId = "vosk-model-small-vn-0.4",
            downloadBytes = 33_656_337L,
            runtimeMemoryBytes = 300_000_000L,
            downloadUrl =
                "https://alphacephei.com/vosk/models/vosk-model-small-vn-0.4.zip",
            downloadSha256 =
                "efe5c8494212110471a79befc48c79da679e5b1fc52a4ffb500222ff86d622e5",
        )

    val all: List<HomiOfflineSpeechModelSpec> = listOf(english, vietnamese)

    fun forLocale(locale: String?): HomiOfflineSpeechModelSpec? {
        val normalized = locale?.trim()?.replace('_', '-')?.lowercase(Locale.US)
        return all.firstOrNull { candidate ->
            normalized == candidate.normalizedLocale ||
                normalized == candidate.normalizedLocale.substringBefore('-')
        }
    }
}

/** App-owned speech model storage. No recorded audio is uploaded here. */
object HomiOfflineSpeechModel {
    private const val stateKey = "state"
    private const val progressKey = "progress"
    private const val errorKey = "error"
    private const val downloadEnabledKey = "downloadEnabled"
    private const val readyMarker = ".homi-ready"

    private val supportedAbis = setOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64")

    fun isRuntimeSupported(): Boolean = Build.SUPPORTED_ABIS.any(supportedAbis::contains)

    fun modelDirectory(
        context: Context,
        spec: HomiOfflineSpeechModelSpec,
    ): File = File(File(context.filesDir, "offline_speech"), spec.modelId)

    fun isInstalled(
        context: Context,
        spec: HomiOfflineSpeechModelSpec,
    ): Boolean {
        val directory = modelDirectory(context, spec)
        val marker = File(directory, readyMarker)
        return try {
            marker.isFile &&
                marker.readText().trim().equals(spec.downloadSha256, ignoreCase = true) &&
                File(directory, "am/final.mdl").isFile &&
                File(directory, "conf/model.conf").isFile &&
                File(directory, "graph/HCLr.fst").isFile &&
                File(directory, "graph/Gr.fst").isFile
        } catch (_: IOException) {
            false
        }
    }

    fun status(
        context: Context,
        spec: HomiOfflineSpeechModelSpec,
    ): Map<String, Any> {
        val preferences = preferences(context, spec)
        val installed = isInstalled(context, spec)
        val state =
            when {
                !isRuntimeSupported() -> "unavailable"
                installed -> "installed"
                preferences.getString(stateKey, null) in setOf("downloading", "pending") ->
                    "pending"
                else -> "missing"
            }
        return mapOf(
            "state" to state,
            "locale" to spec.locale,
            "modelId" to spec.modelId,
            "downloadBytes" to spec.downloadBytes,
            "runtimeMemoryBytes" to spec.runtimeMemoryBytes,
            "progress" to if (installed) 100 else preferences.getInt(progressKey, 0),
            "error" to (preferences.getString(errorKey, "") ?: ""),
            "appManaged" to true,
            "apiLevel" to Build.VERSION.SDK_INT,
        )
    }

    fun scheduleDownload(
        context: Context,
        spec: HomiOfflineSpeechModelSpec,
    ): Map<String, Any> {
        if (!isRuntimeSupported() || isInstalled(context, spec)) {
            return status(context, spec)
        }
        preferences(context, spec).edit().putBoolean(downloadEnabledKey, true).apply()
        setState(context, spec, "pending", progress = 0)
        val constraints =
            Constraints.Builder()
                .setRequiredNetworkType(NetworkType.UNMETERED)
                .setRequiresStorageNotLow(true)
                .build()
        val request =
            OneTimeWorkRequestBuilder<HomiOfflineSpeechModelDownloadWorker>()
                .setInputData(
                    workDataOf(HomiOfflineSpeechModelDownloadWorker.localeKey to spec.locale),
                )
                .setConstraints(constraints)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .addTag(spec.workName)
                .build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            spec.workName,
            ExistingWorkPolicy.REPLACE,
            request,
        )
        return status(context, spec) + ("scheduled" to true)
    }

    fun cancelDownload(
        context: Context,
        spec: HomiOfflineSpeechModelSpec? = null,
    ) {
        val targets = spec?.let(::listOf) ?: HomiOfflineSpeechModels.all
        for (target in targets) {
            preferences(context, target)
                .edit()
                .putBoolean(downloadEnabledKey, false)
                .apply()
            WorkManager.getInstance(context.applicationContext).cancelUniqueWork(target.workName)
            if (!isInstalled(context, target)) {
                setState(context, target, "missing", progress = 0)
            }
        }
    }

    internal fun archiveFile(
        context: Context,
        spec: HomiOfflineSpeechModelSpec,
    ): File = File(File(context.filesDir, "offline_speech"), "${spec.modelId}.zip.part")

    internal fun stagingDirectory(
        context: Context,
        spec: HomiOfflineSpeechModelSpec,
    ): File = File(File(context.filesDir, "offline_speech"), "${spec.modelId}.staging")

    internal fun setState(
        context: Context,
        spec: HomiOfflineSpeechModelSpec,
        state: String,
        progress: Int,
        error: String = "",
    ) {
        preferences(context, spec)
            .edit()
            .putString(stateKey, state)
            .putInt(progressKey, progress.coerceIn(0, 100))
            .putString(errorKey, error)
            .apply()
    }

    internal fun markInstalled(
        context: Context,
        spec: HomiOfflineSpeechModelSpec,
    ) {
        File(modelDirectory(context, spec), readyMarker).writeText(spec.downloadSha256)
        setState(context, spec, "installed", progress = 100)
    }

    internal fun hasValidatedWifi(context: Context): Boolean =
        try {
            val manager = context.getSystemService(ConnectivityManager::class.java) ?: return false
            val network = manager.activeNetwork ?: return false
            val capabilities = manager.getNetworkCapabilities(network) ?: return false
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        } catch (_: SecurityException) {
            false
        }

    internal fun isDownloadEnabled(
        context: Context,
        spec: HomiOfflineSpeechModelSpec,
    ): Boolean = preferences(context, spec).getBoolean(downloadEnabledKey, false)

    private fun preferences(
        context: Context,
        spec: HomiOfflineSpeechModelSpec,
    ) = context.getSharedPreferences(
        "homi.offline-speech-model.${spec.normalizedLocale}.v2",
        Context.MODE_PRIVATE,
    )
}

class HomiOfflineSpeechModelDownloadWorker(
    appContext: Context,
    workerParameters: WorkerParameters,
) : Worker(appContext, workerParameters) {
    private val spec = HomiOfflineSpeechModels.forLocale(inputData.getString(localeKey))

    override fun doWork(): Result {
        val target = spec ?: return Result.failure()
        if (!HomiOfflineSpeechModel.isDownloadEnabled(applicationContext, target)) {
            return Result.failure()
        }
        if (HomiOfflineSpeechModel.isInstalled(applicationContext, target)) {
            HomiOfflineSpeechModel.setState(applicationContext, target, "installed", 100)
            return Result.success()
        }
        if (!HomiOfflineSpeechModel.hasValidatedWifi(applicationContext)) {
            HomiOfflineSpeechModel.setState(applicationContext, target, "pending", 0)
            return Result.retry()
        }

        val archive = HomiOfflineSpeechModel.archiveFile(applicationContext, target)
        val staging = HomiOfflineSpeechModel.stagingDirectory(applicationContext, target)
        return try {
            Log.i(logTag, "Starting app-owned ${target.locale} model download")
            archive.parentFile?.mkdirs()
            staging.deleteRecursively()
            HomiOfflineSpeechModel.setState(applicationContext, target, "downloading", 0)
            downloadAndVerify(target, archive)
            extractAndInstall(target, archive, staging)
            archive.delete()
            HomiOfflineSpeechModel.markInstalled(applicationContext, target)
            Log.i(logTag, "App-owned ${target.locale} model installed")
            Result.success()
        } catch (error: Exception) {
            Log.w(logTag, "App-owned ${target.locale} model download failed", error)
            if (error is InvalidModelArchiveException) archive.delete()
            staging.deleteRecursively()
            HomiOfflineSpeechModel.setState(
                applicationContext,
                target,
                when {
                    !HomiOfflineSpeechModel.isDownloadEnabled(applicationContext, target) ->
                        "missing"
                    runAttemptCount < maxDownloadAttempts -> "pending"
                    else -> "failed"
                },
                ((archive.length() * 100) / target.downloadBytes).toInt().coerceIn(0, 99),
                error.message ?: error.javaClass.simpleName,
            )
            if (
                HomiOfflineSpeechModel.isDownloadEnabled(applicationContext, target) &&
                runAttemptCount < maxDownloadAttempts
            ) {
                Result.retry()
            } else {
                Result.failure()
            }
        }
    }

    private fun downloadAndVerify(
        target: HomiOfflineSpeechModelSpec,
        destination: File,
    ) {
        if (destination.length() == target.downloadBytes) {
            verifyChecksum(target, destination)
            return
        }
        var resumeOffset = destination.length().coerceAtMost(target.downloadBytes)
        if (destination.length() > target.downloadBytes) {
            destination.delete()
            resumeOffset = 0
        }
        val connection =
            (URL(target.downloadUrl).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15_000
                readTimeout = 30_000
                instanceFollowRedirects = true
                requestMethod = "GET"
                if (resumeOffset > 0) setRequestProperty("Range", "bytes=$resumeOffset-")
            }
        try {
            connection.connect()
            if (connection.responseCode !in 200..299) {
                throw IOException("Model download HTTP ${connection.responseCode}")
            }
            val appending =
                resumeOffset > 0 && connection.responseCode == HttpURLConnection.HTTP_PARTIAL
            if (!appending) resumeOffset = 0
            val declaredLength = connection.contentLengthLong
            val expectedResponseBytes = target.downloadBytes - resumeOffset
            if (declaredLength > 0 && declaredLength != expectedResponseBytes) {
                throw InvalidModelArchiveException("Unexpected model archive size: $declaredLength")
            }

            var received = resumeOffset
            var lastProgress = -1
            BufferedInputStream(connection.inputStream).use { input ->
                BufferedOutputStream(FileOutputStream(destination, appending)).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        if (
                            isStopped ||
                            !HomiOfflineSpeechModel.isDownloadEnabled(applicationContext, target)
                        ) {
                            throw DownloadPausedException("Model download stopped")
                        }
                        val count = input.read(buffer)
                        if (count < 0) break
                        received += count
                        if (received > target.downloadBytes) {
                            throw InvalidModelArchiveException(
                                "Model archive exceeded expected size",
                            )
                        }
                        output.write(buffer, 0, count)
                        val progress = ((received * 100) / target.downloadBytes).toInt()
                        if (progress != lastProgress) {
                            lastProgress = progress
                            HomiOfflineSpeechModel.setState(
                                applicationContext,
                                target,
                                "downloading",
                                progress,
                            )
                        }
                    }
                }
            }
            if (received != target.downloadBytes) {
                throw IOException("Incomplete model archive: $received bytes")
            }
            verifyChecksum(target, destination)
        } finally {
            connection.disconnect()
        }
    }

    private fun verifyChecksum(
        target: HomiOfflineSpeechModelSpec,
        archive: File,
    ) {
        val digest = MessageDigest.getInstance("SHA-256")
        BufferedInputStream(FileInputStream(archive)).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val actualHash = digest.digest().joinToString("") { "%02x".format(it) }
        if (!actualHash.equals(target.downloadSha256, ignoreCase = true)) {
            throw InvalidModelArchiveException("Model archive checksum mismatch")
        }
    }

    private fun extractAndInstall(
        target: HomiOfflineSpeechModelSpec,
        archive: File,
        staging: File,
    ) {
        staging.mkdirs()
        val stagingRoot = staging.canonicalFile
        var extractedBytes = 0L
        var entries = 0
        ZipInputStream(BufferedInputStream(FileInputStream(archive))).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (
                    isStopped ||
                    !HomiOfflineSpeechModel.isDownloadEnabled(applicationContext, target)
                ) {
                    throw DownloadPausedException("Model installation stopped")
                }
                entries += 1
                if (entries > maxArchiveEntries) {
                    throw InvalidModelArchiveException("Too many model files")
                }
                val normalized = entry.name.replace('\\', '/')
                val relative = normalized.removePrefix("${target.modelId}/")
                if (relative.isEmpty() || relative == normalized) {
                    zip.closeEntry()
                    continue
                }
                val outputFile = File(stagingRoot, relative).canonicalFile
                if (!outputFile.path.startsWith(stagingRoot.path + File.separator)) {
                    throw InvalidModelArchiveException("Unsafe model archive path")
                }
                if (entry.isDirectory) {
                    outputFile.mkdirs()
                } else {
                    outputFile.parentFile?.mkdirs()
                    BufferedOutputStream(FileOutputStream(outputFile)).use { output ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            if (
                                isStopped ||
                                !HomiOfflineSpeechModel.isDownloadEnabled(
                                    applicationContext,
                                    target,
                                )
                            ) {
                                throw DownloadPausedException("Model installation stopped")
                            }
                            val count = zip.read(buffer)
                            if (count < 0) break
                            extractedBytes += count
                            if (extractedBytes > maxExtractedBytes) {
                                throw InvalidModelArchiveException(
                                    "Extracted model exceeded safety limit",
                                )
                            }
                            output.write(buffer, 0, count)
                        }
                    }
                }
                zip.closeEntry()
            }
        }

        val required =
            listOf("am/final.mdl", "conf/model.conf", "graph/HCLr.fst", "graph/Gr.fst")
        if (required.any { !File(staging, it).isFile }) {
            throw InvalidModelArchiveException("Downloaded model is incomplete")
        }
        val installed = HomiOfflineSpeechModel.modelDirectory(applicationContext, target)
        installed.deleteRecursively()
        if (!staging.renameTo(installed)) {
            throw IOException("Could not activate downloaded model")
        }
    }

    companion object {
        const val localeKey = "locale"
        private const val logTag = "HomiOfflineModel"
        private const val maxDownloadAttempts = 5
        private const val maxArchiveEntries = 512
        private const val maxExtractedBytes = 200_000_000L
    }

    private class InvalidModelArchiveException(message: String) : IOException(message)
    private class DownloadPausedException(message: String) : IOException(message)
}
