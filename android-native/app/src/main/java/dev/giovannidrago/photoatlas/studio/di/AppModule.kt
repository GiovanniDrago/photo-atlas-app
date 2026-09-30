package dev.giovannidrago.photoatlas.studio.di

import android.content.Context
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import dev.giovannidrago.photoatlas.studio.BuildConfig
import dev.giovannidrago.photoatlas.studio.data.auth.SessionManager
import dev.giovannidrago.photoatlas.studio.data.device.DeviceMediaSource
import dev.giovannidrago.photoatlas.studio.data.device.MediaStoreDeviceMediaSource
import dev.giovannidrago.photoatlas.studio.data.auth.TokenProvider
import dev.giovannidrago.photoatlas.studio.data.local.ApiBaseUrlProvider
import dev.giovannidrago.photoatlas.studio.data.local.SettingsStore
import dev.giovannidrago.photoatlas.studio.data.security.KeystoreSecureStorage
import dev.giovannidrago.photoatlas.studio.data.security.SecureStorage
import java.util.concurrent.TimeUnit
import javax.inject.Named
import javax.inject.Singleton
import kotlinx.serialization.json.Json
import okhttp3.Authenticator
import okhttp3.ConnectionPool
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor

@Module
@InstallIn(SingletonComponent::class)
object AppModule {
	@Provides
	@Singleton
	fun json(): Json = Json {
		ignoreUnknownKeys = true
		explicitNulls = false
		encodeDefaults = true
		isLenient = true
	}

	@Provides
	@Singleton
	fun secureStorage(@ApplicationContext context: Context): SecureStorage =
		KeystoreSecureStorage(context)

	@Provides
	@Singleton
	fun apiBaseUrlProvider(store: SettingsStore): ApiBaseUrlProvider = store

	@Provides
	@Singleton
	fun tokenProvider(sessions: SessionManager): TokenProvider = sessions

	@Provides
	@Singleton
	fun deviceMediaSource(source: MediaStoreDeviceMediaSource): DeviceMediaSource = source

	@Provides
	@Singleton
	@Named("plain")
	fun plainClient(): OkHttpClient = OkHttpClient.Builder()
		.connectTimeout(8, TimeUnit.SECONDS)
		.readTimeout(30, TimeUnit.SECONDS)
		.writeTimeout(30, TimeUnit.SECONDS)
		// No connection reuse: through the phone's localhost port bridge the
		// keep-alive stream can desync on large responses ("Unexpected status
		// line"), so every request gets a fresh connection.
		.connectionPool(ConnectionPool(0, 1, TimeUnit.NANOSECONDS))
		.addInterceptor(
			HttpLoggingInterceptor().apply {
				level = if (BuildConfig.DEBUG) {
					HttpLoggingInterceptor.Level.BASIC
				} else {
					HttpLoggingInterceptor.Level.NONE
				}
			},
		)
		.build()

	@Provides
	@Singleton
	@Named("api")
	fun apiClient(
		@Named("plain") plain: OkHttpClient,
		sessions: SessionManager,
	): OkHttpClient {
		val authenticator = Authenticator { _, response ->
			if (response.request.header("Authorization") == null) return@Authenticator null
			if (response.priorResponse != null) return@Authenticator null
			val token = sessions.refreshBlocking() ?: return@Authenticator null
			response.request.newBuilder().header("Authorization", "Bearer $token").build()
		}
		return plain.newBuilder()
			.addInterceptor { chain ->
				val token = sessions.currentToken()
				val request = if (token.isNullOrBlank()) {
					chain.request()
				} else {
					chain.request().newBuilder().header("Authorization", "Bearer $token").build()
				}
				chain.proceed(request)
			}
			.authenticator(authenticator)
			.build()
	}
}
