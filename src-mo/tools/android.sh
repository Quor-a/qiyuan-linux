#!/bin/bash
# android —— 生成 Android 工程（用墨语言写的程序，三条上手机路径）
#
#   ./tools/android.sh <app.mo> <pkg> [java|ndk|web] [-o DIR]
#
#   java : 用 Java 后端生成 MainActivity.java，跑在 ART 上（最常见路径）
#   ndk  : 用 C 后端生成 JNI 动态库 + CMakeLists，跑在 native 层
#   web  : 用 JS 后端生成 WebView 里的页面
#
# 本机没有 Android SDK / NDK，所以**这里只生成工程，不构建 APK**。
# 生成后需要：
#   export ANDROID_HOME=~/Android/Sdk
#   cd <DIR> && ./gradlew assembleDebug
set -e
cd "$(dirname "$0")/.."
ROOT=$PWD
SRC="$1"; PKG="${2:-com.example.moapp}"; MODE="${3:-java}"; OUT="${4:-/tmp/mo_android}"
case "$SRC" in /*) ;; *) SRC="$ROOT/$SRC";; esac
[ -f "$SRC" ] || { echo "找不到 $SRC"; exit 1; }
command -v ./bin/mo2x >/dev/null || [ -x ./bin/mo2x ] || { echo "先编出 bin/mo2x"; exit 1; }

APP=$(basename "$SRC" .mo)
PKGDIR=$(echo "$PKG" | tr '.' '/')
rm -rf "$OUT"; mkdir -p "$OUT"

echo "生成 Android 工程：$MODE / $PKG / $APP -> $OUT"

# ---------- 公共骨架 ----------
mkdir -p "$OUT/app/src/main/res/values"
cat > "$OUT/settings.gradle" <<G
rootProject.name = '$APP'
include ':app'
G
cat > "$OUT/build.gradle" <<G
buildscript {
    repositories { google(); mavenCentral() }
    dependencies { classpath 'com.android.tools.build:gradle:8.1.0' }
}
allprojects {
    repositories { google(); mavenCentral() }
}
G
cat > "$OUT/gradle.properties" <<G
org.gradle.jvmargs=-Xmx2048m
android.useAndroidX=true
G
cat > "$OUT/app/src/main/AndroidManifest.xml" <<G
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="$PKG">
    <application android:label="$APP" android:theme="@style/AppTheme">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
G
cat > "$OUT/app/src/main/res/values/styles.xml" <<G
<resources>
    <style name="AppTheme" parent="android:Theme.Material.Light"/>
</resources>
G
cat > "$OUT/README.md" <<G
# $APP（墨语言生成）

模式：$MODE
包名：$PKG

## 构建

    export ANDROID_HOME=~/Android/Sdk
    ./gradlew assembleDebug

产物：app/build/outputs/apk/debug/app-debug.apk

## 说明

本机生成时**没有 Android SDK**，所以只有工程骨架与源码，
未做实际构建。这是刻意写清楚的，避免"看起来构建过了"。
G

# ---------- 模式 1：Java / ART ----------
if [ "$MODE" = "java" ]; then
  mkdir -p "$OUT/app/src/main/java/$PKGDIR"
  cat > "$OUT/app/build.gradle" <<G
apply plugin: 'com.android.application'
android {
    namespace '$PKG'
    compileSdk 34
    defaultConfig { applicationId '$PKG'; minSdk 24; targetSdk 34; versionCode 1; versionName '1.0' }
}
dependencies { }
G
  {
    echo "package $PKG;"
    echo ""
    echo "// 由墨语言 Java 后端生成（mo2x java）"
    echo "// 原始源码：$(basename "$SRC")"
    echo "public final class MainActivity extends android.app.Activity {"
    echo "    @Override protected void onCreate(android.os.Bundle b) {"
    echo "        super.onCreate(b);"
    echo "        android.widget.TextView tv = new android.widget.TextView(this);"
    echo "        long r = Mo.run();"
    echo "        tv.setText(\"result = \" + r);"
    echo "        setContentView(tv);"
    echo "    }"
    echo "}"
    echo ""
    echo "class Mo {"
  } >> "$OUT/app/src/main/java/$PKGDIR/MainActivity.java"
  ./bin/mo2x "$SRC" java >> "$OUT/app/src/main/java/$PKGDIR/MainActivity.java" 2>/tmp/mo2x_java.err || {
    echo "Java 后端转译失败："; head -3 /tmp/mo2x_java.err; }
  echo "}" >> "$OUT/app/src/main/java/$PKGDIR/MainActivity.java"
fi

# ---------- 模式 2：NDK / C ----------
if [ "$MODE" = "ndk" ]; then
  mkdir -p "$OUT/app/src/main/cpp" "$OUT/app/src/main/java/$PKGDIR"
  cat > "$OUT/app/build.gradle" <<G
apply plugin: 'com.android.application'
android {
    namespace '$PKG'
    compileSdk 34
    defaultConfig {
        applicationId '$PKG'; minSdk 24; targetSdk 34; versionCode 1; versionName '1.0'
        externalNativeBuild { cmake { cppFlags '' } }
    }
    externalNativeBuild { cmake { path 'src/main/cpp/CMakeLists.txt' } }
}
G
  ./bin/mo2x "$SRC" c > "$OUT/app/src/main/cpp/native.c" 2>/tmp/mo2x_c.err || {
    echo "C 后端转译失败："; head -3 /tmp/mo2x_c.err; }
  cat > "$OUT/app/src/main/cpp/CMakeLists.txt" <<G
cmake_minimum_required(VERSION 3.22)
add_library(mo_native SHARED native.c jni_bridge.c)
target_link_libraries(mo_native log)
G
  cat > "$OUT/app/src/main/cpp/jni_bridge.c" <<G
#include <jni.h>
long long mo_main(void);
JNIEXPORT jlong JNICALL
Java_${PKG//./_}_MainActivity_runMo(JNIEnv* env, jobject thiz) {
    return (jlong) mo_main();
}
G
  cat > "$OUT/app/src/main/java/$PKGDIR/MainActivity.java" <<G
package $PKG;
public final class MainActivity extends android.app.Activity {
    static { System.loadLibrary("mo_native"); }
    public static native long runMo();
    @Override protected void onCreate(android.os.Bundle b) {
        super.onCreate(b);
        android.widget.TextView tv = new android.widget.TextView(this);
        tv.setText("result = " + runMo());
        setContentView(tv);
    }
}
G
fi

# ---------- 模式 3：WebView / JS ----------
if [ "$MODE" = "web" ]; then
  mkdir -p "$OUT/app/src/main/assets" "$OUT/app/src/main/java/$PKGDIR"
  cat > "$OUT/app/build.gradle" <<G
apply plugin: 'com.android.application'
android {
    namespace '$PKG'
    compileSdk 34
    defaultConfig { applicationId '$PKG'; minSdk 24; targetSdk 34; versionCode 1; versionName '1.0' }
}
G
  ./bin/mo2x "$SRC" js > "$OUT/app/src/main/assets/app.js" 2>/tmp/mo2x_js.err || {
    echo "JS 后端转译失败："; head -3 /tmp/mo2x_js.err; }
  cat > "$OUT/app/src/main/assets/index.html" <<G
<!doctype html><html><body><pre id="o">running...</pre>
<script src="app.js"></script></body></html>
G
  cat > "$OUT/app/src/main/java/$PKGDIR/MainActivity.java" <<G
package $PKG;
public final class MainActivity extends android.app.Activity {
    @Override protected void onCreate(android.os.Bundle b) {
        super.onCreate(b);
        android.webkit.WebView wv = new android.webkit.WebView(this);
        wv.getSettings().setJavaScriptEnabled(true);
        wv.loadUrl("file:///android_asset/index.html");
        setContentView(wv);
    }
}
G
fi

echo "完成。文件："
find "$OUT" -type f | sed "s|$OUT|  .|" | sort
