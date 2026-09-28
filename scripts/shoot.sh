#!/usr/bin/env bash
# 시뮬레이터에 앱을 깔아 켜고 화면을 찍는다(깃허브 맥 · .github/workflows/ios.yml 이 부른다).
#
#   bash scripts/shoot.sh <앱 경로(.app)> <결과 폴더>
#
# 기기마다(아이폰 · 아이패드):
#   1) 밝은 모드 · 어두운 모드에서 «처음 깐 앱» 을 켜고, 켠 뒤 정해 둔 때에 화면을 찍는다(실제 속도).
#   2) 켜는 장면을 8배 느리게 돌려 영상으로 담는다(밝은 · 어두운 모드). 받은 쪽에서 8배 빠르게 돌리면 실제 장면이다.
#      실제 속도로 녹화하면 녹화(영상 압축)가 맥을 붙잡아 장면이 통째로 건너뛰어졌다(2026-09-28 첫 실행).
#   3) 홈 화면(앱 아이콘)을 찍는다.
# 앱 기록(subsystem app.medqraft.qatelier)과 앱이 기억한 값(사이트 바탕색)도 남긴다.
#
# 명령 하나가 멈춰도 나머지를 계속 찍도록 명령마다 제한 시간을 두고, 진행을 progress.txt 에 남긴다
# (작업이 도중에 끊겨도 올라간 결과에서 어디까지 갔는지 보인다).
set -uo pipefail

APP="$1"
OUT="$2"
BUNDLE="app.medqraft.qatelier"
SLOW=8
mkdir -p "$OUT"
test -d "$APP" || { echo "앱이 없습니다: $APP"; exit 1; }

note() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$OUT/progress.txt"; }

# 정해 둔 초가 지나면 명령을 끊는다(맥에는 timeout 명령이 없다). alarm 은 exec 뒤에도 남는다
limit() {
  local s="$1"
  shift
  perl -e 'alarm shift; exec @ARGV or die "실행 못 함: $!\n"' "$s" "$@"
  local code=$?
  [ "$code" -eq 142 ] && note "제한 시간 ${s}초를 넘겨 끊음: $*"
  return "$code"
}

# 소수점 초 단위 시계. 맥의 date 는 1초보다 잘게 재지 못해 perl 을 쓴다
now() { perl -MTime::HiRes=time -e 'printf "%.2f\n", time'; }
sleep_until() { perl -MTime::HiRes=time,sleep -e 'my $d = $ARGV[0] - time; sleep($d) if $d > 0' "$1"; }
load1() { sysctl -n vm.loadavg | awk '{print $2}'; }

# 처음 부팅한 시뮬레이터는 몇 분 동안 뒤에서 일을 해 맥이 바쁘다(첫 실행에서 앱 켜기가 20~80초 걸림).
# 1분 평균 부하가 코어 수 아래로 내려올 때까지(최대 limit_s 초) 기다린다
settle() {
  local limit_s="$1" cores t0
  cores=$(sysctl -n hw.ncpu)
  t0=$(date +%s)
  while :; do
    if awk -v l="$(load1)" -v c="$cores" 'BEGIN { exit !(l < c) }'; then break; fi
    [ $(( $(date +%s) - t0 )) -ge "$limit_s" ] && { note "부하가 안 내려감(코어 $cores · 부하 $(load1)) · 그대로 찍음"; return; }
    sleep 10
  done
  note "맥이 한가해짐(코어 $cores · 부하 $(load1) · $(( $(date +%s) - t0 ))초 기다림)"
}

fresh_install() {
  local udid="$1"
  limit 60 xcrun simctl uninstall "$udid" "$BUNDLE" >/dev/null 2>&1
  limit 120 xcrun simctl install "$udid" "$APP" || { note "설치 실패"; return 1; }
}

launch() {
  local udid="$1"
  shift
  limit 30 xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1
  limit 90 xcrun simctl launch "$udid" "$BUNDLE" -AppleLanguages "(ko)" -AppleLocale ko_KR "$@" >/dev/null
}

shoot_run() {
  local udid="$1" name="$2" times="$3"
  shift 3
  local start t
  start=$(now)
  launch "$udid" "$@" || note "$name 켜기 실패"
  printf '%s 켜기 명령 %.2fs\n' "$name" "$(perl -e "printf '%.2f', $(now) - $start")" >> "$OUT/timing.txt"
  for t in $times; do
    sleep_until "$(perl -e "printf '%.2f', $start + $t")"
    limit 20 xcrun simctl io "$udid" screenshot --type=png "$OUT/$name-${t}s.png" >/dev/null 2>&1 \
      || echo "$name ${t}s 촬영 실패" >> "$OUT/timing.txt"
    printf '%s %ss → 실제 %.2fs\n' "$name" "$t" "$(perl -e "printf '%.2f', $(now) - $start")" >> "$OUT/timing.txt"
  done
  note "$name 촬영 끝"
}

# 녹화를 멈춘다. SIGINT 를 받아야 영상 파일을 마무리하므로 먼저 INT, 안 멈추면 끊는다
stop_recording() {
  local pid="$1" i
  pkill -INT -f "recordVideo" 2>/dev/null || true
  kill -INT "$pid" 2>/dev/null || true
  for i in $(seq 1 60); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
  done
  if kill -0 "$pid" 2>/dev/null; then
    note "녹화가 15초 안에 안 멈춰 끊음(영상이 깨졌을 수 있음)"
    pkill -KILL -f "recordVideo" 2>/dev/null || true
    kill -KILL "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
}

# 켜는 장면을 SLOW 배 느리게 돌려 녹화한다. 장면(1.2초 + 걷기 0.28초)이 느려져 약 12초가 된다
record_slow() {
  local udid="$1" name="$2" rec
  fresh_install "$udid" || return
  xcrun simctl io "$udid" recordVideo --codec=h264 --force "$OUT/$name.mp4" >/dev/null 2>&1 &
  rec=$!
  sleep 2
  launch "$udid" -QALaunchTimeScale "$SLOW" || note "$name 켜기 실패"
  sleep 20
  stop_recording "$rec"
  note "$name 녹화 끝($(du -h "$OUT/$name.mp4" 2>/dev/null | cut -f1))"
}

shoot_device() {
  local label="$1" udid="$2" look
  limit 30 xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 >/dev/null 2>&1

  # 길들이기: 한 번 켜 두면 웹 엔진 · 망 준비가 데워진다. 찍지 않는다
  limit 30 xcrun simctl ui "$udid" appearance light
  fresh_install "$udid" && launch "$udid" && sleep 20
  note "[$label] 길들이기 끝"

  for look in light dark; do
    limit 30 xcrun simctl ui "$udid" appearance "$look"
    fresh_install "$udid" || continue
    shoot_run "$udid" "$label-$look" "0.3 0.7 1.1 1.6 3 6 12"
    limit 30 xcrun simctl spawn "$udid" defaults read "$BUNDLE" > "$OUT/$label-$look-defaults.txt" 2>&1
  done

  for look in light dark; do
    limit 30 xcrun simctl ui "$udid" appearance "$look"
    record_slow "$udid" "$label-$look-launch-x$SLOW"
  done

  # 홈 화면: 앱을 닫으면 홈이 보인다(아이콘 확인)
  limit 30 xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1
  sleep 3
  limit 20 xcrun simctl io "$udid" screenshot --type=png "$OUT/$label-home.png" >/dev/null 2>&1

  limit 180 xcrun simctl spawn "$udid" log show --last 60m --style compact \
    --predicate 'subsystem == "app.medqraft.qatelier"' > "$OUT/$label-log.txt" 2>&1
  note "[$label] 앱 기록 받음"
  limit 60 xcrun simctl shutdown "$udid" >/dev/null 2>&1
}

# 제한 시간 도우미가 이 맥에서 정말 끊는지 먼저 한 번 본다(142 면 끊은 것)
limit 1 sleep 5 >/dev/null 2>&1
note "제한 시간 도우미 자체 확인: 코드 $? (142 면 정상)"

# 빌드된 앱의 아이콘 · 설정 목록(아이콘이 홈 화면에 안 보이면 여기부터 본다)
cp "$APP"/AppIcon*.png "$OUT/" 2>/dev/null || note "앱 안에 AppIcon 그림이 없음"
plutil -p "$APP/Info.plist" > "$OUT/Info.plist.txt" 2>&1

# 두 기기를 함께 부팅해 둔다(처음 부팅이 몇 분씩 걸려 차례로 하면 두 배가 된다).
# 둘 다 부팅을 마치고 맥이 한가해진 뒤 한 기기씩 찍어, 켜는 장면을 재는 동안 다른 일이 끼지 않게 한다
note "기기 만들기 · 코어 $(sysctl -n hw.ncpu) · 메모리 $(( $(sysctl -n hw.memsize) / 1073741824 ))GB"
PHONE=$(xcrun simctl create "qa-phone" "iPhone 17") || { note "아이폰 기기를 못 만듦"; exit 1; }
PAD=$(xcrun simctl create "qa-pad" "iPad Air 11-inch (M4)") || { note "아이패드 기기를 못 만듦"; exit 1; }
note "phone=$PHONE pad=$PAD"
for u in "$PHONE" "$PAD"; do limit 60 xcrun simctl boot "$u" >/dev/null 2>&1; done
for u in "$PHONE" "$PAD"; do limit 900 xcrun simctl bootstatus "$u" -b >/dev/null 2>&1 || note "부팅을 끝까지 못 기다림: $u"; done
note "두 기기 부팅 끝 · 부하 $(load1)"
settle 300

shoot_device phone "$PHONE"
settle 120
shoot_device pad "$PAD"

# 앱이 꺼졌다면 맥의 진단 기록에 남는다
mkdir -p "$OUT/crashes"
find "$HOME/Library/Logs/DiagnosticReports" -name 'QAtelier*' -newer "$APP" -exec cp {} "$OUT/crashes/" \; 2>/dev/null || true
note "끝"
ls -la "$OUT" "$OUT/crashes"
