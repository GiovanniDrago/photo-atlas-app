package dev.giovannidrago.photoatlas.studio.ui.components

import android.graphics.Bitmap
import android.graphics.Color
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

/** Renders an otpauth/enroll URI as a QR code (zxing core, no extra views). */
@Composable
fun QrCode(
	data: String,
	size: Dp = 200.dp,
	modifier: Modifier = Modifier,
) {
	val bitmap = remember(data) { buildQrBitmap(data) }
	if (bitmap == null) {
		Text(data)
		return
	}
	Image(
		bitmap = bitmap.asImageBitmap(),
		contentDescription = null,
		modifier = modifier
			.size(size)
			.background(androidx.compose.ui.graphics.Color.White)
			.padding(8.dp),
	)
}

private fun buildQrBitmap(data: String): Bitmap? {
	if (data.isBlank()) return null
	return runCatching {
		val dimension = 512
		val matrix = QRCodeWriter().encode(data, BarcodeFormat.QR_CODE, dimension, dimension)
		val pixels = IntArray(dimension * dimension)
		for (y in 0 until dimension) {
			for (x in 0 until dimension) {
				pixels[y * dimension + x] = if (matrix[x, y]) Color.BLACK else Color.WHITE
			}
		}
		Bitmap.createBitmap(pixels, dimension, dimension, Bitmap.Config.ARGB_8888)
	}.getOrNull()
}
