#!/bin/bash
# Ethnir - Space: full APK mod pipeline (idempotent)
# 1) Rename  2) B&W theme  3) Smali perf surgery  4) Rebuild/align/sign
set -e
cd Space

GREEN='\033[0;32m'; NC='\033[0m'
say(){ echo -e "${GREEN}==>${NC} $1"; }

# ============ 1. RENAME ============
say "Renaming app to 'Ethnir - Space'"
sed -i 's|<string name="app_name">𝙴𝚁𝚁𝙾𝚁 - 𝚂𝙿𝙰𝙲𝙴𝚂</string>|<string name="app_name">Ethnir - Space</string>|' res/values/strings.xml
find res/values-* -name strings.xml -exec sed -i \
  's|<string name="app_name">[^<]*</string>|<string name="app_name">Ethnir - Space</string>|' {} \; 2>/dev/null || true

say "Renaming launcher label in AndroidManifest.xml"
python3 - <<'PYEOF'
src = open("AndroidManifest.xml", encoding="utf-8").read()
old = 'android:label="&#120436;&#120449;&#120449;&#120446;&#120449; - &#120450;&#120447;&#120432;&#120434;&#120436;"'
new = 'android:label="Ethnir - Space"'
if old in src:
    assert src.count(old) == 1
    open("AndroidManifest.xml", "w", encoding="utf-8").write(src.replace(old, new))
    print("  ok: manifest label -> Ethnir - Space")
elif 'android:label="Ethnir - Space"' in src:
    print("  skip: manifest label already renamed")
else:
    raise AssertionError("manifest label literal not found")
PYEOF

say "Bumping version to 2.4.0 (51)"
sed -i 's|versionCode: 50|versionCode: 51|; s|versionName: 2.3.1|versionName: 2.4.0|' apktool.yml

# ============ 2. BLACK & WHITE THEME ============
say "Applying black & white palette"
sed -i 's|#2aa05a|#ffffff|g; s|#2AA05A|#ffffff|g; s|#882aa05a|#88ffffff|g;
        s|#03c27c|#e0e0e0|g; s|#41bf3e|#cccccc|g;
        s|#11a1fd|#ffffff|g; s|#046eb2|#b0b0b0|g; s|#248bff|#ffffff|g;
        s|#ff4081|#ffffff|g; s|#e40e1d|#8a8a8a|g' res/values/colors.xml
# NOTE: keep the *_black dark-mode twin entries — their resource IDs are pinned
# in res/values/public.xml and deleting them breaks aapt2 linking.

say "Recoloring Pangle SDK assets"
find res -path "*bytedance*" \( -name "*.png" -o -name "*.webp" \) | while read -r f; do
  mogrify -colorspace Gray "$f" 2>/dev/null || true
done

say "Fixing ids.xml self-closing id tags for aapt"
sed -i 's|<id name="\([^"]*\)" />|<item type="id" name="\1"/>|g' res/values/ids.xml

# ============ 3. SMALI PERF SURGERY ============
python3 - <<'PYEOF'
import re, sys

def replace_method(path, sig, new_body, marker="ETHNIR-MOD"):
    src = open(path).read()
    if marker in src.split(sig, 1)[-1].split(".end method", 1)[0] if sig in src else False:
        print(f"  skip (already patched): {path}")
        return
    start = src.find(sig)
    assert start != -1, f"method not found in {path}: {sig}"
    end = src.find(".end method", start)
    assert end != -1, f"no end method for {sig}"
    end += len(".end method")
    open(path, "w").write(src[:start] + new_body + src[end:])

def sub_once(path, old, new, marker="ETHNIR-MOD"):
    src = open(path).read()
    if marker in src and old not in src:
        print(f"  skip (already patched): {path}")
        return
    assert old in src, f"pattern not found in {path}: {old[:70]}"
    open(path, "w").write(src.replace(old, new))

# --- 1. Pangle SDK init -> no-op ---
p = "smali_classes3/com/gspace/android/data/ads/ll1111llllI1l/lIIIl11ll11.smali"
if "ETHNIR-MOD" not in open(p).read():
    src = open(p).read()
    start = src.find(".method private static IlIl1I111IIII(Landroid/content/Context;)V")
    assert start != -1
    end = src.find(".end method", start) + len(".end method")
    new = """.method private static IlIl1I111IIII(Landroid/content/Context;)V
    .locals 0

    # ETHNIR-MOD: Pangle SDK init disabled (perf: no ad network spin-up)
    return-void
.end method"""
    open(p, "w").write(src[:start] + new + src[end:])
    print("  ok: TTAdSdk.init neutralized")
else:
    print("  skip: TTAdSdk.init already neutralized")

# --- 2. TTAdNative getter -> always null (kills lazy-init fallback too) ---
replace_method(
    p,
    ".method public static IlIl1I111IIII()Lcom/bytedance/sdk/openadsdk/TTAdNative;",
    """.method public static IlIl1I111IIII()Lcom/bytedance/sdk/openadsdk/TTAdNative;
    .locals 1

    # ETHNIR-MOD: never return a live ad loader (init disabled, no lazy re-init)
    const/4 v0, 0x0

    return-object v0
.end method""",
)
print("  ok: TTAdNative getter returns null")

# --- 3. HwAds.init -> nop ---
sub_once(
    "smali_classes3/com/gspace/android/data/ads/IIIIIlI1IIIl1.smali",
    "    invoke-static {p1}, Lcom/huawei/hms/ads/HwAds;->init(Landroid/content/Context;)V",
    "    # ETHNIR-MOD: HwAds.init disabled\n    nop",
)
print("  ok: HwAds.init -> nop")

# --- 4. Pangle splash load -> nop ---
sub_once(
    "smali/com/gspace/android/data/ads/ll11II1lIIllI.smali",
    "    invoke-interface {v1, v0, v2, p1}, Lcom/bytedance/sdk/openadsdk/TTAdNative;->loadSplashAd(Lcom/bytedance/sdk/openadsdk/AdSlot;Lcom/bytedance/sdk/openadsdk/TTAdNative$CSJSplashAdListener;I)V",
    "    # ETHNIR-MOD: splash ad load disabled\n    nop\n    nop\n    nop\n    nop",
)
print("  ok: loadSplashAd -> nop")

# --- 5. Pangle banner + fullscreen loads -> nop ---
sub_once(
    "smali/com/gspace/android/data/ads/IlIllI1l1l1II/Il1llll111.smali",
    "    invoke-interface {v0, p1, v1}, Lcom/bytedance/sdk/openadsdk/TTAdNative;->loadFullScreenVideoAd(Lcom/bytedance/sdk/openadsdk/AdSlot;Lcom/bytedance/sdk/openadsdk/TTAdNative$FullScreenVideoAdListener;)V",
    "    # ETHNIR-MOD: fullscreen video ad load disabled\n    nop\n    nop\n    nop",
)
sub_once(
    "smali/com/gspace/android/data/ads/IlIllI1l1l1II/Il1llll111.smali",
    "    invoke-interface {v0, p3, v2}, Lcom/bytedance/sdk/openadsdk/TTAdNative;->loadBannerExpressAd(Lcom/bytedance/sdk/openadsdk/AdSlot;Lcom/bytedance/sdk/openadsdk/TTAdNative$NativeExpressAdListener;)V",
    "    # ETHNIR-MOD: banner express ad load disabled\n    nop\n    nop\n    nop",
)
print("  ok: banner + fullscreen loaders -> nop")

# --- 6. Keep-alive engine off ---
replace_method(
    "smali_classes3/com/gspace/watchdog/WatchDog.smali",
    ".method public startWatch()V",
    """.method public startWatch()V
    .locals 10

    # ETHNIR-MOD: keep-alive engine disabled (perf: no silent music, no
    # dual-process daemon, no wallpaper/1px activity, no account sync)
    return-void
.end method""",
)
print("  ok: WatchDog.startWatch disabled")
PYEOF

# ============ 4. REBUILD / SIGN ============
say "Rebuilding APK with apktool"
say "Rebuilding APK with apktool 3.0.3 (bundled aapt2)"
java -Xmx2g -jar /tmp/apktool.jar b -f -j 2 -o /tmp/ethnir_unsigned.apk .

say "Zipaligning"
zipalign -f -p 4 /tmp/ethnir_unsigned.apk /tmp/ethnir_aligned.apk

say "Signing"
if [ ! -f /tmp/ethnir.keystore ]; then
  keytool -genkeypair -keystore /tmp/ethnir.keystore -alias ethnir \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass ethnir123 -keypass ethnir123 \
    -dname "CN=Ethnir Space, OU=Ethnir, O=Ethnir, L=Internet, ST=Internet, C=US" 2>/dev/null
fi
apksigner sign --ks /tmp/ethnir.keystore --ks-pass pass:ethnir123 \
  --key-pass pass:ethnir123 --out /tmp/ethnir-signed.apk /tmp/ethnir_aligned.apk

say "Verifying signature"
apksigner verify /tmp/ethnir-signed.apk && echo "  signature OK"

cp /tmp/ethnir-signed.apk ../public/ethnir-space-v2.4.0.apk
say "Done: public/ethnir-space-v2.4.0.apk"
