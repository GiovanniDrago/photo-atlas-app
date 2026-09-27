import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
	alias(libs.plugins.android.application)
	alias(libs.plugins.kotlin.compose)
	alias(libs.plugins.kotlin.serialization)
}

val localProperties = Properties().apply {
	val file = rootProject.file("local.properties")
	if (file.exists()) {
		file.inputStream().use { load(it) }
	}
}

val keystorePassword: String? =
	System.getenv("KEYSTORE_PASSWORD") ?: localProperties.getProperty("KEYSTORE_PASSWORD")
val keystoreKeyPassword: String? =
	System.getenv("KEY_PASSWORD") ?: keystorePassword
val keystoreAlias: String =
	System.getenv("KEY_ALIAS") ?: localProperties.getProperty("KEY_ALIAS") ?: "photoatlas"
val keystoreFile = rootProject.file("release.keystore")

android {
	namespace = "dev.giovannidrago.photoatlas.studio"
	compileSdk = 37

	defaultConfig {
		applicationId = "dev.giovannidrago.photoatlas.studio"
		minSdk = 26
		targetSdk = 37
		versionCode = 1
		versionName = "0.1.0"
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

	testImplementation(libs.junit)
	testImplementation(libs.kotlinx.coroutines.test)
}
