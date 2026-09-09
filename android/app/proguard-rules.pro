# JNA accesses these members from libjnidispatch by their Java names. R8 must
# not rename Pointer.peer or the Vosk model fails to initialize in release APKs.
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }
-dontwarn java.awt.**

# ML Kit discovers component registrars by their manifest class names and
# reflectively invokes their no-argument constructors. Release R8 optimisation
# can otherwise rename/remove those constructors, leaving offline translation
# unavailable even though its language models are installed.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
