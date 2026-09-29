# kotlinx.serialization: release builds are minified with R8, so keep the
# generated serializers, their descriptors and the API DTO fields intact.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

-keep,includedescriptorclasses class dev.giovannidrago.photoatlas.studio.**$$serializer { *; }
-keepclassmembers class dev.giovannidrago.photoatlas.studio.** {
    *** Companion;
}
-keepclasseswithmembers class dev.giovannidrago.photoatlas.studio.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# The API DTOs are decoded through their generated serializers: never rename
# or strip their fields.
-keep class dev.giovannidrago.photoatlas.studio.data.remote.** { *; }
