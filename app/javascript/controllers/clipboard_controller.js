import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static values = { text: String }

  copy() {
    navigator.clipboard.writeText(this.textValue).then(() => {
      // 成功メッセージ表示
      const originalText = this.element.textContent;
      this.element.textContent = 'コピーしました！';
      this.element.classList.add('text-green-600');

      setTimeout(() => {
        this.element.textContent = originalText;
        this.element.classList.remove('text-green-600');
      }, 2000);
    }).catch((err) => {
      console.error('クリップボードへのコピーに失敗しました:', err);
      alert('コピーに失敗しました');
    });
  }
}
