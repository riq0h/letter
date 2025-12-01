(function() {
  'use strict';

  const embeds = new Map();

  function generateId() {
    return Math.random().toString(36).substr(2, 9);
  }

  function init() {
    // 埋め込み要素を探す
    document.querySelectorAll('div.letter-embed').forEach(function(container) {
      const embedUrl = container.getAttribute('data-embed-url');
      if (!embedUrl) return;

      const id = generateId();
      const iframe = document.createElement('iframe');

      iframe.src = embedUrl;
      iframe.width = '100%';
      iframe.height = '400';  // 初期高さ
      iframe.style.border = 'none';
      iframe.style.overflow = 'hidden';
      iframe.style.display = 'block';
      iframe.sandbox = 'allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox';
      iframe.setAttribute('loading', 'lazy');
      iframe.setAttribute('scrolling', 'no');

      embeds.set(id, iframe);

      iframe.onload = function() {
        iframe.contentWindow.postMessage({
          type: 'setHeight',
          id: id
        }, '*');
      };

      // コンテナの中身をクリアしてiframeだけを残す
      container.innerHTML = '';
      container.appendChild(iframe);

      // コンテナのスタイルをリセット
      container.style.margin = '0';
      container.style.padding = '0';
      container.style.border = 'none';
      container.style.background = 'none';
      container.style.overflow = 'hidden';
    });
  }

  // 高さ調整メッセージを受信
  window.addEventListener('message', function(e) {
    if (e.data && e.data.type === 'setHeight' && e.data.height) {
      embeds.forEach(function(iframe) {
        if (iframe.contentWindow === e.source) {
          iframe.height = e.data.height;
        }
      });
    }
  });

  // DOMContentLoaded後に実行
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
