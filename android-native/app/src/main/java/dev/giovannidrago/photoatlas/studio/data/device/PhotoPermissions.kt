package dev.giovannidrago.photoatlas.studio.data.device

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat

/** Runtime permissions needed to read the device media library. */
object PhotoPermissions {
	fun required(): List<String> = buildList {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
			add(Manifest.permission.READ_MEDIA_IMAGES)
			add(Manifest.permission.READ_MEDIA_VIDEO)
		} else {
			add(Manifest.permission.READ_EXTERNAL_STORAGE)
		}
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
			add(Manifest.permission.ACCESS_MEDIA_LOCATION)
		}
	}

	fun has(context: Context): Boolean = required().all { permission ->
		ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
	}

	fun openSettings(context: Context) {
		val intent = Intent(
			Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
			Uri.fromParts("package", context.packageName, null),
		).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
		runCatching { context.startActivity(intent) }
	}
}
