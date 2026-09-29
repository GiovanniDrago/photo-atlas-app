import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
	alias(libs.plugins.android.application)
	alias(libs.plugins.kotlin.compose)
	alias(libs.plugins.kotlin.serialization)
	alias(libs.plugins.hilt.android)
	alias(libs.plugins.ksp)
}

val localProperties = Properties().apply {
	val file = rootProject.file("local.properties")
	if (file.exists()) {
		file.inputStream().use { load(it) }
	}
}

fun envOrNull(name: String): String? = System.getenv(name)?.takeIf { it.isNotBlank() }

// Empty secrets must fall back (the keystore uses the same password for store
// and key, or KEY_PASSWORD is unset).
val keystorePassword: String? =
	envOrNull("KEYSTORE_PASSWORD") ?: localProperties.getProperty("KEYSTORE_PASSWORD")
val keystoreKeyPassword: String? =
	envOrNull("KEY_PASSWORD") ?: keystorePassword
val keystoreAlias: String =
	envOrNull("KEY_ALIAS") ?: localProperties.getProperty("KEY_ALIAS") ?: "photoatlas"
val keystoreFile = rootProject.file("release.keystore")

android {
	namespace = "dev.giovannidrago.photoatlas.studio"
	compileSdk = 37

	defaultConfig {
		applicationId = "dev.giovannidrago.photoatlas.studio"
		minSdk = 26
		targetSdk = 37
		versionCode = 13
		versionName = "0.7.4"
	}

	signingConfigs {
		if (keystoreFile.exists()) {
			create("release") {
				storeFile = keystoreFile
				storePassword = keystorePassword
				keyAlias = keystoreAlias
				keyPassword = keystoreKeyPassword
			}
		}
	}

	buildTypes {
		release {
			signingConfig = signingConfigs.findByName("release")
			isMinifyEnabled = true
			isShrinkResources = true
			proguardFiles(
				getDefaultProguardFile("proguard-android-optimize.txt"),
				"proguard-rules.pro",
			)
		}
	}

	compileOptions {
		sourceCompatibility = JavaVersion.VERSION_17
		targetCompatibility = JavaVersion.VERSION_17
	}

	buildFeatures {
		compose = true
		buildConfig = true
	}

	testOptions {
		unitTests {
			isReturnDefaultValues = true
		}
	}
}

kotlin {
	compilerOptions {
		jvmTarget = JvmTarget.JVM_17
	}
}

dependencies {
	val composeBom = platform(libs.compose.bom)
	implementation(composeBom)
	implementation(libs.compose.ui)
	implementation(libs.compose.ui.tooling.preview)
	implementation(libs.compose.material3)
	implementation(libs.compose.material.icons.extended)
	debugImplementation(libs.compose.ui.tooling)

	implementation(libs.androidx.navigation.compose)
	implementation(libs.androidx.lifecycle.viewmodel.compose)
	implementation(libs.androidx.lifecycle.runtime.compose)
	implementation(libs.androidx.core.ktx)
	implementation(libs.androidx.activity.compose)

	implementation(libs.hilt.android)
	ksp(libs.hilt.compiler)
	implementation(libs.androidx.hilt.navigation.compose)

	implementation(libs.retrofit)
	implementation(libs.retrofit.kotlinx.serialization.converter)
	implementation(libs.okhttp)
	implementation(libs.okhttp.logging.interceptor)
	implementation(libs.kotlinx.serialization.json)

	implementation(libs.androidx.datastore.preferences)
	implementation(libs.zxing.core)
	implementation(libs.coil.compose)
	implementation(libs.coil.video)
	implementation(libs.osmdroid.android)

	testImplementation(libs.junit)
	testImplementation(libs.kotlinx.coroutines.test)
	testImplementation(libs.mockk)
	testImplementation(libs.okhttp.mockwebserver)
	testImplementation(libs.androidx.datastore.preferences.core)
	testImplementation(libs.retrofit)
	testImplementation(libs.retrofit.kotlinx.serialization.converter)
}
