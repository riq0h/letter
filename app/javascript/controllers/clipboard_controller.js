import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static values = { text: String }
  static targets = [ "icon" ]

  copy() {
    navigator.clipboard.writeText(this.textValue).then(() => {
      // アイコンをチェックマークに切り替え
      const originalHTML = this.iconTarget.innerHTML;
      this.iconTarget.innerHTML = `
        <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      `;
      this.element.classList.remove('text-gray-400');
      this.element.classList.add('text-green-600');

      setTimeout(() => {
        this.iconTarget.innerHTML = originalHTML;
        this.element.classList.remove('text-green-600');
        this.element.classList.add('text-gray-400');
      }, 2000);
    }).catch((err) => {
      console.error('クリップボードへのコピーに失敗しました:', err);
      alert('コピーに失敗しました');
    });
  }
}
