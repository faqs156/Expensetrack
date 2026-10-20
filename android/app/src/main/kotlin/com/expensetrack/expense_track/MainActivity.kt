package com.expensetrack.expense_track

import android.app.backup.BackupManager
import android.content.ContentValues
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.expensetrack.expense_track/data_survival"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleCloudBackup" -> {
                        BackupManager(applicationContext).dataChanged()
                        result.success(true)
                    }
                    "writeSurvivingBackup" -> {
                        val json = call.argument<String>("json")
                        if (json.isNullOrEmpty()) {
                            result.error("bad_args", "Missing json", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(writeSurvivingBackup(json))
                        } catch (e: Exception) {
                            result.error("write_failed", e.message, null)
                        }
                    }
                    "readSurvivingBackup" -> {
                        try {
                            result.success(readSurvivingBackup())
                        } catch (e: Exception) {
                            result.error("read_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun backupDisplayName() = "expense_track_autobackup.json"
    private fun backupRelativePath() =
        Environment.DIRECTORY_DOCUMENTS + "/ExpenseTrack"

    private fun findBackupUri(): Uri? {
        val resolver = applicationContext.contentResolver
        val collection = MediaStore.Files.getContentUri("external")
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection =
            "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?"
        val args = arrayOf(backupDisplayName(), "%ExpenseTrack%")
        resolver.query(collection, projection, selection, args, null).use { cursor ->
            if (cursor != null && cursor.moveToFirst()) {
                val id = cursor.getLong(0)
                return Uri.withAppendedPath(collection, id.toString())
            }
        }
        return null
    }

    private fun writeSurvivingBackup(json: String): Boolean {
        val resolver = applicationContext.contentResolver
        val bytes = json.toByteArray(Charsets.UTF_8)
        val existing = findBackupUri()
        if (existing != null) {
            resolver.openOutputStream(existing, "wt")?.use { out ->
                out.write(bytes)
                return true
            }
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, backupDisplayName())
            put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
            put(MediaStore.MediaColumns.RELATIVE_PATH, backupRelativePath())
        }
        val uri = resolver.insert(MediaStore.Files.getContentUri("external"), values)
            ?: return false
        resolver.openOutputStream(uri)?.use { out ->
            out.write(bytes)
        } ?: return false
        return true
    }

    private fun readSurvivingBackup(): String? {
        val uri = findBackupUri() ?: return null
        return applicationContext.contentResolver.openInputStream(uri)?.use { input ->
            input.readBytes().toString(Charsets.UTF_8)
        }
    }
}
