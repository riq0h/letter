ARG RUBY_VERSION=3.4.1
FROM ruby:$RUBY_VERSION-slim AS base

# 基本システム依存関係をインストール
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    curl \
    jq \
    libsqlite3-0 \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# ビルドステージ
FROM base AS builder

# ビルド用依存関係をインストール
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    libsqlite3-dev \
    nodejs \
    npm \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# 作業ディレクトリを設定
WORKDIR /app

# 依存関係ファイルをコピー
COPY --link Gemfile Gemfile.lock ./
COPY --link package*.json ./

# Bundlerを設定してgemをインストール
RUN bundle config --global path /usr/local/bundle && \
    bundle install --jobs 4 --retry 3 && \
    bundle binstubs --all --path /usr/local/bundle/bin && \
    rm -rf ~/.bundle/cache

# Node.js依存関係をインストール
RUN npm ci --production && \
    npm cache clean --force

# アプリケーションコードをコピー
COPY --link . .

# アセットをプリコンパイル（本番ビルド用のダミーシークレット使用）
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

# 実行時ステージ
FROM base AS runner

# 実行時依存関係をインストール（ヘルスチェック用procpsとnpm含む）
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    procps \
    nodejs \
    npm && \
    rm -rf /var/lib/apt/lists/*

# 作業ディレクトリを設定
WORKDIR /app

# セキュリティのため非rootユーザーを作成
RUN groupadd --system --gid 1000 letter && \
    useradd letter --uid 1000 --gid 1000 --create-home --shell /bin/bash

# ビルダーステージから成果物をコピー
COPY --from=builder --chown=letter:letter /app /app
COPY --from=builder --chown=letter:letter /usr/local/bundle /usr/local/bundle

# bundlerのPATHと環境変数を設定
ENV PATH="/app/bin:/usr/local/bundle/bin:$PATH"
ENV BUNDLE_GEMFILE="/app/Gemfile"
ENV BUNDLE_PATH="/usr/local/bundle"

# 必要なディレクトリを適切な権限で作成
RUN mkdir -p \
    tmp/pids \
    tmp/cache \
    log \
    storage \
    public/uploads \
    && chown -R letter:letter /app

# エントリーポイントスクリプトをコピー
COPY --chown=letter:letter docker/entrypoint.sh /usr/bin/entrypoint.sh
RUN chmod +x /usr/bin/entrypoint.sh

# 非rootユーザーに切り替え
USER letter

# ポートを公開
EXPOSE 3000

# エントリーポイントを設定
ENTRYPOINT ["entrypoint.sh"]

# デフォルトコマンド
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]