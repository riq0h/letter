#!/bin/bash
set -euo pipefail

# letter バックアップスクリプト
# WALモードのSQLiteデータベースを安全にバックアップし、オブジェクトストレージにアップロード

# 設定項目
INSTANCE_DIR="/home/example/letter"
BACKUP_DIR="/home/example/letter/backup"
BACKUP_LIFETIME_DAYS=7
DATE_FORMAT="%Y%m%d_%H-%M-%S"
WEB_CONTAINER="letter-web-1"
RCLONE_DESTINATION="r2:letter-backup"

# バックアップ対象データベース (パス:名前)
DATABASES=(
	"storage/production.sqlite3:primary"
	"storage/queue_production.sqlite3:queue"
	"storage/cable_production.sqlite3:cable"
	"storage/cache_production.sqlite3:cache"
)

# ログ用カラーコード
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ログ出力関数
log() {
	echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
	echo -e "${RED}[エラー]${NC} $1" >&2
}

success() {
	echo -e "${GREEN}[成功]${NC} $1"
}

warn() {
	echo -e "${YELLOW}[警告]${NC} $1"
}

# ディレクトリ作成
mkdir -p "$BACKUP_DIR"

# エラーハンドリング
trap 'error "バックアップが失敗しました (行: $LINENO)"; exit 1' ERR

log "🚀 letter SQLite バックアップを開始します..."
cd "$INSTANCE_DIR"

# コンテナが動作中か確認
if ! docker ps --format "table {{.Names}}" | grep -q "^${WEB_CONTAINER}$"; then
	error "コンテナ ${WEB_CONTAINER} が実行されていません"
	exit 1
fi

# タイムスタンプ付きバックアップファイル名を作成
BACKUP_TIMESTAMP=$(date +$DATE_FORMAT)
BACKUP_ARCHIVE="$BACKUP_DIR/letter_backup_${BACKUP_TIMESTAMP}.tar.gz"

# 一時ディレクトリ作成
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

log "📊 SQLiteデータベースをバックアップ中 (WALモード対応)..."

# 各データベースをバックアップ
backup_success=true
for db_info in "${DATABASES[@]}"; do
	IFS=':' read -r db_path db_name <<<"$db_info"

	log "  📁 $db_name データベースを処理中..."

	if docker exec $WEB_CONTAINER test -f "/app/$db_path"; then
		# 元のファイルサイズを取得
		original_size=$(docker exec $WEB_CONTAINER stat -c%s "/app/$db_path" 2>/dev/null || echo "0")

		# SQLite .backupコマンドを使用してバックアップ (WALモードに対応)
		backup_temp="/tmp/${db_name}_backup_$(date +%s).sqlite3"

		if docker exec $WEB_CONTAINER sqlite3 "/app/$db_path" ".backup $backup_temp"; then
			# バックアップをコンテナからホストにコピー
			docker cp "$WEB_CONTAINER:$backup_temp" "$TEMP_DIR/${db_name}.sqlite3"

			# コンテナ内の一時ファイルを削除
			docker exec $WEB_CONTAINER rm -f "$backup_temp"

			# バックアップを検証
			if [[ -f "$TEMP_DIR/${db_name}.sqlite3" ]]; then
				backup_size=$(stat -c%s "$TEMP_DIR/${db_name}.sqlite3" 2>/dev/null || echo "0")
				success "    ✅ $db_name: $(numfmt --to=iec $original_size) → $(numfmt --to=iec $backup_size)"
			else
				error "    ❌ $db_name のバックアップコピーに失敗しました"
				backup_success=false
			fi
		else
			error "    ❌ $db_name のSQLiteバックアップコマンドが失敗しました"
			backup_success=false
		fi
	else
		warn "    ⚠️ $db_name が見つかりません: $db_path"
	fi
done

if [ "$backup_success" = false ]; then
	error "一部のデータベースバックアップが失敗しました"
	exit 1
fi

# 設定ファイルのバックアップ
log "⚙️ 設定ファイルをバックアップ中..."
CONFIG_FILES=(
	"docker-compose.yml"
	"docker-compose.prod.yml"
	"Dockerfile"
	".env"
)

for config_file in "${CONFIG_FILES[@]}"; do
	if [[ -f "$config_file" ]]; then
		cp "$config_file" "$TEMP_DIR/" 2>/dev/null && log "    📄 $config_file" || true
	fi
done

# nginx設定があればコピー
if [[ -d "nginx" ]]; then
	cp -r nginx "$TEMP_DIR/" 2>/dev/null && log "    📄 nginx/" || true
fi

# バックアップマニフェストを作成
log "📝 バックアップマニフェストを作成中..."
cat >"$TEMP_DIR/backup_manifest.txt" <<EOF
letter SQLite バックアップマニフェスト
=====================================
作成日時: $(date '+%Y-%m-%d %H:%M:%S %Z')
ホスト名: $(hostname)
コンテナ: $WEB_CONTAINER
バックアップID: $BACKUP_TIMESTAMP

データベースファイル:
$(for db_info in "${DATABASES[@]}"; do
	IFS=':' read -r db_path db_name <<<"$db_info"
	if [[ -f "$TEMP_DIR/${db_name}.sqlite3" ]]; then
		size=$(stat -c%s "$TEMP_DIR/${db_name}.sqlite3")
		echo "  $db_name.sqlite3: $(numfmt --to=iec $size)"
	fi
done)

設定ファイル:
$(find "$TEMP_DIR" -maxdepth 1 -type f \( -name "*.yml" -o -name "Dockerfile*" -o -name ".env*" \) -exec basename {} \; | sort | sed 's/^/  /')

総ファイル数: $(find "$TEMP_DIR" -type f | wc -l)
EOF

# 圧縮アーカイブを作成
log "📦 圧縮アーカイブを作成中..."
tar -czf "$BACKUP_ARCHIVE" -C "$TEMP_DIR" .

# アーカイブを検証
if [[ -f "$BACKUP_ARCHIVE" ]]; then
	archive_size=$(stat -c%s "$BACKUP_ARCHIVE")
	success "✅ アーカイブ作成完了: $(basename "$BACKUP_ARCHIVE") ($(numfmt --to=iec $archive_size))"

	# アーカイブの整合性をテスト
	if tar -tzf "$BACKUP_ARCHIVE" >/dev/null 2>&1; then
		success "✅ アーカイブの整合性を確認しました"
	else
		error "❌ アーカイブの破損を検出しました"
		exit 1
	fi
else
	error "❌ アーカイブの作成に失敗しました"
	exit 1
fi

# 古いローカルバックアップを削除
log "🧹 古いローカルバックアップを削除中..."
find "$BACKUP_DIR" -name "letter_backup_*.tar.gz" -mtime +$BACKUP_LIFETIME_DAYS -delete 2>/dev/null || true
local_backups=$(find "$BACKUP_DIR" -name "letter_backup_*.tar.gz" | wc -l)
log "📁 保持されているローカルバックアップ数: $local_backups"

# rcloneが利用可能な場合はオブジェクトストレージにアップロード
if command -v rclone >/dev/null 2>&1; then
	log "🔄 オブジェクトストレージにアップロード中..."

	if rclone copy "$BACKUP_ARCHIVE" "$RCLONE_DESTINATION/" --progress --stats-one-line; then
		success "✅ アップロードが正常に完了しました"

		# 古いリモートバックアップを削除
		log "🧹 古いリモートバックアップを削除中..."
		rclone delete "$RCLONE_DESTINATION" --min-age "${BACKUP_LIFETIME_DAYS}d" --include "letter_backup_*.tar.gz" 2>/dev/null || true

		# リモートバックアップ数を確認
		remote_backups=$(rclone ls "$RCLONE_DESTINATION" --include "letter_backup_*.tar.gz" 2>/dev/null | wc -l || echo "不明")
		log "☁️ リモートバックアップ数: $remote_backups"
	else
		warn "⚠️ アップロードに失敗しました - バックアップはローカルに保存されています"
	fi
else
	warn "ℹ️ rcloneがインストールされていません - リモートバックアップをスキップします"
fi

# サマリーを生成
total_db_size=$(docker exec $WEB_CONTAINER du -sb /app/storage/*.sqlite3 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
compression_ratio=$(echo "scale=1; $archive_size * 100 / $total_db_size" | bc -l 2>/dev/null || echo "N/A")

log "📈 バックアップ要約:"
log "  🎯 letter"
log "  📊 元のDBサイズ: $(numfmt --to=iec $total_db_size)"
log "  📦 アーカイブサイズ: $(numfmt --to=iec $archive_size)"
log "  📉 圧縮率: ${compression_ratio}%"
log "  📍 ローカルパス: $BACKUP_DIR"
log "  🕐 保持期間: $BACKUP_LIFETIME_DAYS 日"

success "👍 letterのバックアップが正常に完了しました! 📬"
