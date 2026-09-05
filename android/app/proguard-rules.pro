# JNA accesses these members from libjnidispatch by their Java names. R8 must
# not rename Pointer.peer or the Vosk model fails to initialize in release APKs.
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }
-dontwarn java.awt.**
