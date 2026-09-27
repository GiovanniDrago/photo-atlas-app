package dev.giovannidrago.photoatlas.studio.data.local

/** Where the API lives; the store behind it changes when the user edits it. */
interface ApiBaseUrlProvider {
	suspend fun currentApiBaseUrl(): String

	suspend fun setApiBaseUrl(value: String)
}
