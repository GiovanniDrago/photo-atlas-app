package dev.giovannidrago.photoatlas.studio

import dev.giovannidrago.photoatlas.studio.data.auth.TokenProvider
import dev.giovannidrago.photoatlas.studio.data.local.ApiBaseUrlProvider
import kotlinx.serialization.json.Json
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.RecordedRequest

internal class FakeBaseUrlProvider(var url: String) : ApiBaseUrlProvider {
	override suspend fun currentApiBaseUrl(): String = url

	override suspend fun setApiBaseUrl(value: String) {
		url = value
	}
}

internal class LambdaDispatcher(
	private val handler: (RecordedRequest) -> MockResponse,
) : Dispatcher() {
	override fun dispatch(request: RecordedRequest): MockResponse = handler(request)
}

internal fun testJson(): Json = Json {
	ignoreUnknownKeys = true
	explicitNulls = false
	encodeDefaults = true
	isLenient = true
}

internal class FakeTokenProvider(var token: String? = null) : TokenProvider {
	override fun currentToken(): String? = token

	override fun refreshBlocking(): String? = token
}
