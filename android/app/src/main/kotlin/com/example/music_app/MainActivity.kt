package com.example.music_app

import android.content.ContentUris
import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : AudioServiceActivity() {
    private val downloadChannelName = "com.example.music_app/downloader"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "downloadMp3") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val url = call.argument<String>("url")
                val title = call.argument<String>("title")
                if (url.isNullOrBlank()) {
                    result.error("invalid_args", "Missing url", null)
                    return@setMethodCallHandler
                }

                Thread {
                    try {
                        val savedPath = downloadToMediaStore(url, title.orEmpty())
                        runOnUiThread { result.success(savedPath) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error(
                                "download_failed",
                                e.message ?: "Failed to download song",
                                null
                            )
                        }
                    }
                }.start()
            }
    }

    private fun downloadToMediaStore(url: String, title: String): String {
        val resolver = applicationContext.contentResolver
        val fileName = "${sanitizeFileName(title.ifBlank { "z_music_${System.currentTimeMillis()}" })}.mp3"
        val normalizedTitle = title.ifBlank { fileName.removeSuffix(".mp3") }
        val contentUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }

        findExistingSong(contentUri, fileName, normalizedTitle)?.let {
            throw IllegalStateException("Song is already in your library.")
        }

        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Audio.Media.MIME_TYPE, "audio/mpeg")
            put(MediaStore.Audio.Media.TITLE, normalizedTitle)
            put(MediaStore.Audio.Media.IS_MUSIC, 1)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Audio.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/Z Music")
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            } else {
                val musicDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
                val appDir = File(musicDir, "Z Music").apply { mkdirs() }
                val targetFile = File(appDir, fileName)
                put(MediaStore.Audio.Media.DATA, targetFile.absolutePath)
            }
        }

        val itemUri = resolver.insert(contentUri, values)
            ?: throw IllegalStateException("Could not create media entry")

        try {
            val attemptUrls = buildList {
                add(url)
                if (url.startsWith("http://")) {
                    add(url.replaceFirst("http://", "https://"))
                }
            }

            var lastError: Exception? = null
            for (attemptUrl in attemptUrls) {
                var connection: HttpURLConnection? = null
                try {
                    connection = openConnectionWithRedirects(attemptUrl)
                    val code = connection.responseCode
                    if (code !in 200..299) {
                        val details = readErrorDetails(connection)
                        throw IllegalStateException("Download failed with HTTP $code${if (details.isNotBlank()) ": $details" else ""}")
                    }

                    resolver.openOutputStream(itemUri, "w")?.use { outputStream ->
                        connection.inputStream.use { inputStream ->
                            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                            while (true) {
                                val read = inputStream.read(buffer)
                                if (read <= 0) break
                                outputStream.write(buffer, 0, read)
                            }
                            outputStream.flush()
                        }
                    } ?: throw IllegalStateException("Could not open destination stream")

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val completedValues = ContentValues().apply {
                            put(MediaStore.Audio.Media.IS_PENDING, 0)
                        }
                        resolver.update(itemUri, completedValues, null, null)
                    }
                    return itemUri.toString()
                } catch (e: Exception) {
                    lastError = e
                } finally {
                    connection?.disconnect()
                }
            }

            throw lastError ?: IllegalStateException("Unknown download failure")
        } catch (e: Exception) {
            resolver.delete(itemUri, null, null)
            throw e
        }
    }

    private fun findExistingSong(contentUri: android.net.Uri, fileName: String, title: String): String? {
        val resolver = applicationContext.contentResolver
        val projection = arrayOf(MediaStore.Audio.Media._ID)

        val (selection, selectionArgs) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Pair(
                "${MediaStore.Audio.Media.RELATIVE_PATH} = ? AND (${MediaStore.Audio.Media.DISPLAY_NAME} = ? OR ${MediaStore.Audio.Media.TITLE} = ?)",
                arrayOf("${Environment.DIRECTORY_MUSIC}/Z Music/", fileName, title)
            )
        } else {
            val musicDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
            val appDir = File(musicDir, "Z Music")
            Pair(
                "${MediaStore.Audio.Media.DATA} LIKE ? AND (${MediaStore.Audio.Media.DISPLAY_NAME} = ? OR ${MediaStore.Audio.Media.TITLE} = ?)",
                arrayOf("${appDir.absolutePath}/%", fileName, title)
            )
        }

        resolver.query(contentUri, projection, selection, selectionArgs, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val id = cursor.getLong(idIndex)
                return ContentUris.withAppendedId(contentUri, id).toString()
            }
        }
        return null
    }

    private fun openConnectionWithRedirects(rawUrl: String, maxRedirects: Int = 8): HttpURLConnection {
        var currentUrl = URL(rawUrl)
        repeat(maxRedirects) {
            val connection = (currentUrl.openConnection() as HttpURLConnection).apply {
                connectTimeout = 20000
                readTimeout = 30000
                instanceFollowRedirects = false
                requestMethod = "GET"
                setRequestProperty(
                    "User-Agent",
                    "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36"
                )
                setRequestProperty("Accept", "*/*")
                setRequestProperty("Referer", "https://www.youtube.com/")
                setRequestProperty("Origin", "https://www.youtube.com")
            }

            val responseCode = connection.responseCode
            if (responseCode in 301..303 || responseCode == 307 || responseCode == 308) {
                val location = connection.getHeaderField("Location")
                connection.disconnect()
                if (location.isNullOrBlank()) {
                    throw IllegalStateException("Redirect response missing location")
                }
                currentUrl = URL(currentUrl, location)
            } else {
                return connection
            }
        }
        throw IllegalStateException("Too many redirects while downloading")
    }

    private fun readErrorDetails(connection: HttpURLConnection): String {
        return try {
            connection.errorStream?.bufferedReader()?.use { reader ->
                reader.readLine()?.trim()?.take(120) ?: ""
            } ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun sanitizeFileName(input: String): String {
        val clean = input.replace(Regex("[\\\\/:*?\"<>|]"), " ").trim()
        return if (clean.isBlank()) "z_music_${System.currentTimeMillis()}" else clean.take(80)
    }
}
