#!/usr/bin/env bash
# 시뮬레이터에 앱을 깔아 켜고 화면을 찍는다(깃허브 맥 · .github/workflows/ios.yml 이 부른다).
#
#   bash scripts/shoot.sh <앱 경로(.app)> <결과 폴더>
#
# 기기마다(아이폰 다음 아이패드. 한 대씩 켜고 끈다):
#   1) 켜는 장면을 8배 느리게 돌려 영상으로 담는다(밝은 · 어두운 모드). 받은 쪽에서 8배 빠르게 돌리면 실제 장면이다.
#      실제 속도로 녹화하면 녹화(영상 압축)가 맥을 붙잡아 장면이 통째로 건너뛰어졌다(2026-09-28 첫 실행).
#   2) 밝은 · 어두운 모드에서 «처음 깐 앱» 을 켜고 정해 둔 때에 화면을 찍는다.
#   3) 홈 화면(앱 아이콘)을 찍는다.
# 앱 기록(subsystem app.medqraft.qatelier)도 남긴다. 앱이 기억한 사이트 바탕색은 기록의 «바탕색» 줄로 본다
# (simctl spawn defaults read 는 앱 데이터 폴더 안의 설정 파일을 못 읽어 «Domain does not exist» 만 나왔다).
#
# 명령 하나가 멈춰도 나머지를 계속 찍도록 명령마다 제한 시간을 두고, 진행을 progress.txt 에 남긴다.
# 전체 시간(SHOOT_BUDGET_S)이 모자라면 남은 촬영을 건너뛰고 앱 기록 · 끄기만 한다(작업 제한 시간에 통째로
# 끊기면 뒤 기기의 기록이 사라졌다. 2026-09-28 둘째 실행).
set -uo pipefail

APP="$1"
OUT="$2"
BUNDLE="app.medqraft.qatelier"
SLOW=8
DEADLINE=$(( $(date +%s) + ${SHOOT_BUDGET_S:-3300} ))
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
swap_used() { sysctl -n vm.swapusage | sed 's/.*used = \([^ ]*\).*/스왑 \1/'; }
enough() { [ $(( DEADLINE - $(date +%s) )) -ge "$1" ]; }

# 처음 부팅한 시뮬레이터는 몇 분 동안 뒤에서 일을 해 맥이 바쁘다(둘을 함께 켠 둘째 실행에서 1분 부하 888 ·
# 앱 켜기 90초 초과. 부하 46 에서는 앱 켜기 2.5초). 1분 부하가 기준 아래로 내려올 때까지(최대 limit_s 초) 기다린다.
# 기다리는 동안 1분마다 부하를 남겨, 이 맥에서 부하가 어떻게 내려가는지 다음 실행에서 볼 수 있게 한다
settle() {
  local limit_s="$1" target t0 l last=0
  target=$(( $(sysctl -n hw.ncpu) * 10 ))
  t0=$(date +%s)
  while :; do
    l=$(load1)
    if awk -v l="$l" -v c="$target" 'BEGIN { exit !(l < c) }'; then
      note "맥이 한가해짐(부하 $l < $target · $(( $(date +%s) - t0 ))초 기다림 · $(swap_used))"
      return
    fi
    if [ $(( $(date +%s) - t0 )) -ge "$limit_s" ] || ! enough 900; then
      note "부하가 안 내려감(부하 $l · 기준 $target · $(swap_used)) · 그대로 찍음"
      return
    fi
    if [ $(( $(date +%s) - last )) -ge 60 ]; then
      note "기다리는 중 · 부하 $l"
      last=$(date +%s)
    fi
    sleep 10
  done
}

# 화면 모드를 바꾸고 바뀌었는지 읽어 본다. 둘째 실행에서 바꾸기가 제한 시간에 끊겨 «밝은 모드» 녹화가
# 어두운 모드로 찍혔다. 읽기 자체가 안 되면(빈 값 등) 바꿨다고 보고 찍되 기록을 남긴다
set_look() {
  local udid="$1" want="$2" got="" i
  for i in 1 2 3; do
    limit 60 xcrun simctl ui "$udid" appearance "$want" >/dev/null 2>&1
    got=$(limit 30 xcrun simctl ui "$udid" appearance 2>/dev/null | tr -d '[:space:]')
    case "$got" in
      "$want") return 0 ;;
      light | dark) sleep 5 ;;
      *)
        note "화면 모드를 읽지 못함(${got:-빈 값}) · $want 로 바뀌었다고 보고 찍음"
        return 0
        ;;
    esac
  done
  note "화면 모드를 $want 로 못 바꿈(지금 $got) · 이 모드는 건너뜀"
  return 1
}

# 앱을 지우고 새로 깐다. 지우기가 안 되면 앞 실행의 기억(사이트 바탕색)이 남아 켜는 장면의 색이 달라진다
fresh_install() {
  local udid="$1"
  limit 90 xcrun simctl uninstall "$udid" "$BUNDLE" >/dev/null 2>&1
  if limit 30 xcrun simctl get_app_container "$udid" "$BUNDLE" data >/dev/null 2>&1; then
    note "앱이 안 지워짐 · 앞 실행의 기억이 남은 채 켜짐"
  fi
  limit 180 xcrun simctl install "$udid" "$APP" || { note "설치 실패"; return 1; }
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

# 기기 하나를 만들어 켜고, 찍고, 끈다. 둘을 함께 켜면 첫 부팅의 뒷일이 겹쳐 맥이 멈추다시피 했다(둘째 실행)
shoot_device() {
  local label="$1" type="$2" udid look
  udid=$(xcrun simctl create "qa-$label" "$type") || { note "[$label] 기기를 못 만듦: $type"; return 1; }
  note "[$label] $type · $udid"
  limit 120 xcrun simctl boot "$udid" >/dev/null 2>&1
  limit 900 xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || note "[$label] 부팅을 끝까지 못 기다림"
  note "[$label] 부팅 끝 · 부하 $(load1)"
  settle 600

  limit 30 xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 >/dev/null 2>&1

  # 길들이기: 한 번 켜 두면 웹 엔진 · 망 준비가 데워진다. 찍지 않는다
  set_look "$udid" light
  fresh_install "$udid" && launch "$udid" && sleep 20
  note "[$label] 길들이기 끝"

  for look in light dark; do
    enough 300 || { note "[$label] 시간이 모자라 $look 녹화를 건너뜀"; continue; }
    set_look "$udid" "$look" || continue
    record_slow "$udid" "$label-$look-launch-x$SLOW"
  done

  for look in light dark; do
    enough 240 || { note "[$label] 시간이 모자라 $look 촬영을 건너뜀"; continue; }
    set_look "$udid" "$look" || continue
    fresh_install "$udid" || continue
    shoot_run "$udid" "$label-$look" "0.5 1.5 4 10"
  done

  # 홈 화면: 앱을 닫으면 홈이 보인다(아이콘 확인)
  limit 30 xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1
  sleep 3
  limit 20 xcrun simctl io "$udid" screenshot --type=png "$OUT/$label-home.png" >/dev/null 2>&1

  limit 180 xcrun simctl spawn "$udid" log show --last 60m --style compact \
    --predicate 'subsystem == "app.medqraft.qatelier"' > "$OUT/$label-log.txt" 2>&1
  note "[$label] 앱 기록 받음"
  limit 60 xcrun simctl shutdown "$udid" >/dev/null 2>&1
  note "[$label] 끔 · 부하 $(load1)"
}

# 제한 시간 도우미가 이 맥에서 정말 끊는지 먼저 한 번 본다(142 면 끊은 것)
limit 1 sleep 5 >/dev/null 2>&1
note "제한 시간 도우미 자체 확인: 코드 $? (142 면 정상)"

# 빌드된 앱의 아이콘 · 설정 목록(아이콘이 홈 화면에 안 보이면 여기부터 본다)
cp "$APP"/AppIcon*.png "$OUT/" 2>/dev/null || note "앱 안에 AppIcon 그림이 없음"
plutil -p "$APP/Info.plist" > "$OUT/Info.plist.txt" 2>&1

note "코어 $(sysctl -n hw.ncpu) · 메모리 $(( $(sysctl -n hw.memsize) / 1073741824 ))GB · 부하 $(load1) · 시간 $(( (DEADLINE - $(date +%s)) / 60 ))분"
shoot_device phone "iPhone 17"
if enough 600; then
  shoot_device pad "iPad Air 11-inch (M4)"
else
  note "[pad] 시간이 모자라 건너뜀"
fi

# 앱이 꺼졌다면 맥의 진단 기록에 남는다
mkdir -p "$OUT/crashes"
find "$HOME/Library/Logs/DiagnosticReports" -name 'QAtelier*' -newer "$APP" -exec cp {} "$OUT/crashes/" \; 2>/dev/null || true
note "끝"
ls -la "$OUT" "$OUT/crashes"
