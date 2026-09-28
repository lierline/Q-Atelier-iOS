// Q-Atelier iOS 앱(WKWebView) 보조 스크립트 (2026-09-28)
//
// 앱이 모든 화면에, 페이지 스크립트보다 먼저 넣는다(WebViewController · WKUserScript atDocumentStart).
// 안드로이드 앱의 bridge.js 를 옮겼고, 다른 점은 셋이다.
//   · 앱과의 통로가 window.webkit.messageHandlers.QAtelierApp 이다(안드로이드는 QAtelierApp 객체).
//   · WKWebView 는 넣을 곳을 도메인으로 고를 수 없어, 우리 화면이 아니면 여기서 스스로 멈춘다.
//     앱도 받은 말의 출처를 다시 본다. 아래 __BRIDGE_HOSTS__ 자리는 앱이 AppConfig.bridgeHosts 로 채운다.
//   · 앱 알림(푸시)은 아직 없다(1단계). window.qatelierApp 을 만들지 않아 사이트는 웹 알림 쪽으로 가고,
//     WKWebView 에는 웹 알림이 없어 «이 브라우저는 알림을 받을 수 없습니다» 를 보인다.
//
// 1) 브라우저 안에서 만든 파일 내려받기(blob · data 주소)를 앱으로 넘긴다. 흔히 click() 바로 뒤에
//    URL.revokeObjectURL 로 주소를 걷으므로, 만들 때 Blob 을 붙잡아 둔다.
// 2) window.print() 를 iOS 인쇄로 잇는다. WKWebView 에서는 print() 가 아무 일도 하지 않는다.
// 3) 화면 바탕색을 앱에 알린다. 앱은 그 색으로 상태 표시줄 · 홈 막대 자리를 칠하고 글자 밝기를 맞춘다.
// 4) 첫 그림이 화면에 나간 때를 앱에 알린다. 앱은 이때 켜는 장면을 걷는다.
(function () {
  var allowed = __BRIDGE_HOSTS__;
  if (location.protocol !== 'https:' || allowed.indexOf(location.hostname) < 0) return;
  var channel = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.QAtelierApp;
  if (window.__qatelierApp || !channel) return;
  window.__qatelierApp = true;

  var blobs = new Map();
  var createUrl = URL.createObjectURL;
  URL.createObjectURL = function (obj) {
    var url = createUrl.apply(URL, arguments);
    if (obj instanceof Blob) blobs.set(url, obj);
    return url;
  };
  var revokeUrl = URL.revokeObjectURL;
  URL.revokeObjectURL = function (url) {
    setTimeout(function () { blobs.delete(url); }, 60000);
    return revokeUrl.apply(URL, arguments);
  };

  function post(msg) {
    channel.postMessage(JSON.stringify(msg));
  }

  function save(href, name) {
    var known = blobs.get(href);
    var getting = known ? Promise.resolve(known) : fetch(href).then(function (r) { return r.blob(); });
    getting
      .then(function (blob) {
        return new Promise(function (ok, fail) {
          var reader = new FileReader();
          reader.onload = function () { ok({ data: String(reader.result), type: blob.type }); };
          reader.onerror = function () { fail(reader.error); };
          reader.readAsDataURL(blob);
        });
      })
      .then(function (r) {
        post({ kind: 'save', name: name || '', type: r.type || '', data: r.data.slice(r.data.indexOf(',') + 1) });
      })
      .catch(function (e) {
        post({ kind: 'save-failed', reason: String((e && e.message) || e) });
      });
  }
  // 앱이 blob 주소를 새 창으로 열려는 것을 받았을 때 부른다(WebViewController openNewWindow)
  window.__qatelierSave = save;

  function isFileLink(a) {
    return !!(a && a.href && (a.href.indexOf('blob:') === 0 || a.href.indexOf('data:') === 0));
  }

  // 문서에 붙이지 않은 a 를 만들어 click() 하는 모양이 흔하다. 그 click 은 문서까지 올라오지 않으므로 여기서 받는다
  var nativeClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    if (isFileLink(this)) {
      save(this.href, this.getAttribute('download'));
      return;
    }
    return nativeClick.apply(this, arguments);
  };
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (isFileLink(a)) {
      e.preventDefault();
      save(a.href, a.getAttribute('download'));
    }
  }, true);

  window.print = function () {
    post({ kind: 'print', title: document.title });
  };

  // 바탕색은 캔버스에 한 번 칠해 #rrggbb 로 바꿔 보낸다(oklch 같은 표기도 받게). 테마를 바꿀 때(html · body 의 속성) ·
  // 폰의 밤낮이 바뀔 때 · 앱으로 돌아올 때 다시 보고, 같은 색이면 보내지 않는다.
  var lastBg = '';
  function hexOf(css) {
    try {
      var c = document.createElement('canvas');
      c.width = 1;
      c.height = 1;
      var x = c.getContext('2d');
      x.fillStyle = css;
      x.fillRect(0, 0, 1, 1);
      var d = x.getImageData(0, 0, 1, 1).data;
      if (d[3] < 255) return '';
      return '#' + [d[0], d[1], d[2]].map(function (n) { return (n < 16 ? '0' : '') + n.toString(16); }).join('');
    } catch (_) {
      return '';
    }
  }
  function pageBg() {
    var els = [document.body, document.documentElement];
    for (var i = 0; i < els.length; i++) {
      if (!els[i]) continue;
      var bg = getComputedStyle(els[i]).backgroundColor;
      if (bg && bg !== 'transparent' && bg !== 'rgba(0, 0, 0, 0)') return hexOf(bg);
    }
    return '';
  }
  function reportTheme() {
    var hex = pageBg();
    if (!hex || hex === lastBg) return;
    lastBg = hex;
    post({ kind: 'theme', bg: hex });
  }
  document.addEventListener('DOMContentLoaded', function () {
    reportTheme();
    var watch = new MutationObserver(reportTheme);
    watch.observe(document.documentElement, { attributes: true, attributeFilter: ['class', 'data-theme', 'style'] });
    if (document.body) watch.observe(document.body, { attributes: true, attributeFilter: ['class', 'style'] });
  });
  window.addEventListener('load', reportTheme);
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) reportTheme();
  });
  if (window.matchMedia) {
    var scheme = window.matchMedia('(prefers-color-scheme: dark)');
    if (scheme.addEventListener) scheme.addEventListener('change', reportTheme);
  }

  // 문서가 선 뒤 두 번째 그리기 차례가 오면 첫 그림은 이미 화면에 나갔다. 화면이 바뀌었다는 소식(commit)만으로
  // 걷으면 첫 그림 전의 빈 바탕이 잠깐 보인다. 안쪽 틀(iframe)은 알리지 않는다
  if (window === window.top) {
    var painted = function () {
      requestAnimationFrame(function () {
        requestAnimationFrame(function () { post({ kind: 'painted' }); });
      });
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', painted);
    else painted();
  }
})();
