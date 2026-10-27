package com.pedidos.sistema_pedidos

import android.content.ContentValues
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity: la necesita local_auth para mostrar el diálogo de huella.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Guarda un archivo en el teléfono: los PDF en Descargas y las imágenes
        // en la galería (carpeta "Distribuidora AM"). Devuelve dónde quedó.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sistema_pedidos/archivos")
            .setMethodCallHandler { call, result ->
                if (call.method != "guardar") return@setMethodCallHandler result.notImplemented()
                val bytes = call.argument<ByteArray>("bytes")
                val nombre = call.argument<String>("nombre")
                val mime = call.argument<String>("mime") ?: "application/octet-stream"
                if (bytes == null || nombre == null) return@setMethodCallHandler result.error("args", "Faltan datos", null)
                try {
                    result.success(guardar(bytes, nombre, mime))
                } catch (e: Exception) {
                    result.error("guardar", e.javaClass.simpleName, null)
                }
            }
    }

    private fun guardar(bytes: ByteArray, nombre: String, mime: String): String {
        val imagen = mime.startsWith("image/")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val carpeta = if (imagen) "${Environment.DIRECTORY_PICTURES}/Distribuidora AM" else Environment.DIRECTORY_DOWNLOADS
            val coleccion = if (imagen) MediaStore.Images.Media.EXTERNAL_CONTENT_URI else MediaStore.Downloads.EXTERNAL_CONTENT_URI
            val datos = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, nombre)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, carpeta)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(coleccion, datos) ?: throw IllegalStateException("No se pudo crear")
            contentResolver.openOutputStream(uri)!!.use { it.write(bytes) }
            datos.clear()
            datos.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(uri, datos, null, null)
            return if (imagen) "Galería" else "Descargas"
        }
        // Android 9 o anterior: directo en la carpeta pública (permiso en el manifiesto).
        val base = Environment.getExternalStoragePublicDirectory(
            if (imagen) Environment.DIRECTORY_PICTURES else Environment.DIRECTORY_DOWNLOADS)
        val dir = if (imagen) File(base, "Distribuidora AM") else base
        dir.mkdirs()
        val file = File(dir, nombre)
        file.writeBytes(bytes)
        MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf(mime), null)
        return if (imagen) "Galería" else "Descargas"
    }
}
