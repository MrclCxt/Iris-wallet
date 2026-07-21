# Regras de keep para o build release com R8/minify.
# Mantém o que é acessado por reflexão ou JNI e não pode ser removido/renomeado.

# Flutter embedding
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# flutter_rust_bridge — ponte JNI para as libs nativas (ldk_node, lwk).
# A bridge chama métodos Java/Dart gerados via JNI: não renomear/remover.
-keep class com.fasterxml.jackson.** { *; }
-keep class * implements java.io.Serializable { *; }
-keepclasseswithmembers class * {
    native <methods>;
}

# NFC (nfc_manager) — usa reflexão sobre as tecnologias de tag do Android
-keep class android.nfc.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# camera / camera_windows / mobile_scanner
-keep class io.flutter.plugins.camerax.** { *; }
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Mantém anotações e assinaturas genéricas (necessário para reflexão/JSON)
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
