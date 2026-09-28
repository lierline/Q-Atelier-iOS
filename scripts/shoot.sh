#!/usr/bin/env bash
# 시뮬레이터에 앱을 깔아 켜고 화면을 찍는다(깃허브 맥 · .github/workflows/ios.yml 이 부른다).
#
#   bash scripts/shoot.sh <앱 경로(.app)> <결과 폴더>
#
# 기기마다 밝은 모드 · 어두운 모드에서 «처음 깐 앱» 을 켜고, 켠 뒤 정해 둔 때에 화면을 찍는다.
# 밝은 모드 첫 판은 켜는 장면을 영상으로도 담는다. 아이폰은 한 번 더, 장면을 8배 느리게 돌려 한 장씩 찍는다.
# 앱 기록(subsystem app.medqraft.qatelier)과 앱이 기억한 값(사이트 바탕색)도 함께 남긴다.
set -euo pipefail

APP="$1"
OUT="$2"
BUNDLE="app.medqraft.qatelier"
mkdir -p "$OUT"
test -d "$APP"

# 소수점 초 단위 시계. 맥의 date 는 1초보다 잘게 재지 못해 perl 을 쓴다
now() { perl -MTime::HiRes=time -e 'printf "%.2f\n", time'; }
sleep_until() { perl -MTime::HiRes=time,sleep -e 'my $d = $ARGV[0] - time; sleep($d) if $d > 0' "$1"; }

shoot_run() {
  local udid="$1" name="$2" times="$3"
  shift 3
  local start
  xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
  start=$(now)
  xcrun simctl launch "$udid" "$BUNDLE" -AppleLanguages "(ko)" -AppleLocale ko_KR "$@" >/dev/null
  for t in $times; do
    sleep_until "$(perl -e "printf '%.2f', $start + $t")"
    xcrun simctl io "$udid" screenshot --type=png "$OUT/$name-${t}s.png" >/dev/null 2>&1 \
      || echo "$name ${t}s 촬영 실패" >> "$OUT/timing.txt"
    printf '%s %ss → 실제 %.2fs\n' "$name" "$t" "$(perl -e "printf '%.2f', $(now) - $start")" >> "$OUT/timing.txt"
  done
}

shoot_device() {
  local label="$1" type="$2"
  local udid
  udid=$(xcrun simctl create "qa-$label" "$type")
  echo "[$label] $type → $udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true

  for look in light dark; do
    xcrun simctl ui "$udid" appearance "$look"
    xcrun simctl uninstall "$udid" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$APP"
    local rec=""
    if [ "$look" = light ]; then
      xcrun simctl io "$udid" recordVideo --codec=h264 --force "$OUT/$label-launch.mp4" >/dev/null 2>&1 &
      rec=$!
      sleep 2
    fi
    shoot_run "$udid" "$label-$look" "0.3 0.7 1.1 1.6 3 6 12"
    if [ -n "$rec" ]; then
      kill -INT "$rec" 2>/dev/null || true
      wait "$rec" 2>/dev/null || true
    fi
    xcrun simctl spawn "$udid" defaults read "$BUNDLE" > "$OUT/$label-$look-defaults.txt" 2>&1 || true
  done

  if [ "$label" = phone ]; then
    # 켜는 장면을 8배 느리게: 1초마다 찍으면 실제 장면의 0.125초 간격이 된다(느림 안내는 실제 8초에 뜬다)
    shoot_run "$udid" "$label-slow" "1 2 3 4 5 6 7 8 9 10 11" -QALaunchTimeScale 8
  fi

  xcrun simctl spawn "$udid" log show --last 30m --style compact \
    --predicate 'subsystem == "app.medqraft.qatelier"' > "$OUT/$label-log.txt" 2>&1 || true
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
}

shoot_device phone "iPhone 17"
shoot_device pad "iPad Air 11-inch (M4)"

# 앱이 꺼졌다면 맥의 진단 기록에 남는다
mkdir -p "$OUT/crashes"
find "$HOME/Library/Logs/DiagnosticReports" -name 'QAtelier*' -newer "$APP" -exec cp {} "$OUT/crashes/" \; 2>/dev/null || true
ls -la "$OUT" "$OUT/crashes"
