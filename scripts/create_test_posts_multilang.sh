#!/bin/bash

# 多言語テスト投稿生成スクリプト
# Usage: ./create_test_posts_multilang.sh

set -e

echo "=== Multilingual Test Posts Generation Script ==="
echo ""

# 環境変数の読み込み
if [ ! -f .env ]; then
    echo "ERROR: .env file not found"
    exit 1
fi

set -a
source .env
set +a

# ユーザー名の入力
read -p "Enter username: " username

echo ""
echo "Creating test posts for user: $username"
echo "Domain: $ACTIVITYPUB_DOMAIN"

# 投稿生成スクリプトの実行
cat > tmp_create_posts.rb << EOF
#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'

username = "$username"
domain = "$ACTIVITYPUB_DOMAIN"
protocol = "$ACTIVITYPUB_PROTOCOL"

begin
  # Find user and get access token
  actor = Actor.find_by(username: username, local: true)
  unless actor
    puts "✗ User '\#{username}' not found"
    exit 1
  end

  # Find access token
  token = Doorkeeper::AccessToken.joins(:application)
                                  .where(resource_owner_id: actor.id)
                                  .order(created_at: :desc)
                                  .first

  unless token
    puts "✗ No access token found for user '\#{username}'"
    puts "Run: ./create_oauth_token.sh"
    exit 1
  end

  puts "Found access token: \#{token.token[0..10]}..."

  BASE_URL = "\#{protocol}://\#{domain}"
  ACCESS_TOKEN = token.token

  def make_api_request(endpoint, method = 'GET', body = nil)
    uri = URI("\#{BASE_URL}\#{endpoint}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    
    case method.upcase
    when 'POST'
      request = Net::HTTP::Post.new(uri)
      request.body = body.to_json if body
      request['Content-Type'] = 'application/json'
    when 'GET'
      request = Net::HTTP::Get.new(uri)
    end
    
    request['Authorization'] = "Bearer \#{ACCESS_TOKEN}"
    
    response = http.request(request)
    
    if response.code.to_i >= 200 && response.code.to_i < 300
      return JSON.parse(response.body) if response.body && !response.body.empty?
    else
      puts "API Error: \#{response.code} \#{response.message}"
      puts response.body if response.body
      return nil
    end
  rescue => e
    puts "Request Error: \#{e.message}"
    return nil
  end

  # English posts
  english_posts = [
    "Hello world! This is my first English test post on this ActivityPub instance.",
    "Testing federation capabilities with this English message. #ActivityPub #Federation",
    "The weather is beautiful today. Perfect for coding and testing new features!",
    "Just discovered this amazing decentralized social network. The future is here! 🚀",
    "Working on improving the user experience. Every small step counts towards progress.",
    "Coffee break time! ☕ Nothing beats a good cup while debugging code.",
    "Exploring the possibilities of open social networks. Freedom and privacy matter.",
    "Another day, another commit. Building the web we want to see in the world.",
    "Testing mentions and hashtags: @\#{username} #OpenSource #ActivityPub #SocialMedia",
    "The beauty of federation is that no single entity controls the entire network.",
    "Learning something new every day. Technology keeps evolving at an amazing pace.",
    "Grateful for the open source community that makes projects like this possible.",
    "Sometimes the simplest solutions are the most elegant ones. Keep it simple! ✨",
    "Debugging is like being a detective in a crime movie where you're also the murderer.",
    "The best code is the code that doesn't need to be written. But we write it anyway.",
    "Version control is a time machine for your code. Git saves the day once again!",
    "Documentation is love letters to your future self. Write them with care. 💝",
    "Every bug is an opportunity to learn something new about the system you're building.",
    "The internet was designed to be decentralized. Let's bring that vision back to life.",
    "Testing complete! All systems operational and ready for the next challenge. 🎯"
  ]

  # Japanese posts
  japanese_posts = [
    "こんにちは！ActivityPubインスタンスでの最初の日本語投稿です。",
    "連合機能のテストを行っています。分散型ソーシャルネットワークの可能性を探索中 #ActivityPub",
    "今日はとても良い天気ですね。コーディングには最適な日です ☀️",
    "オープンソースプロジェクトの素晴らしさを改めて感じています。",
    "プログラミングは創造的な行為だと思います。何もないところから何かを作り出す。",
    "コーヒーを飲みながらのデバッグタイム ☕ 集中力が高まります。",
    "分散型ネットワークの未来について考えています。自由で開かれたインターネットを。",
    "小さな改善の積み重ねが、大きな変化を生み出すのだと信じています。",
    "テスト投稿：メンションとハッシュタグ @\#{username} #オープンソース #技術",
    "技術の進歩によって、より良い世界を作ることができると信じています。",
    "毎日新しいことを学ぶのが楽しいです。知識は共有することで価値が生まれる。",
    "コミュニティの力は素晴らしい。一人では成し遂げられないことも、みんなでなら。",
    "シンプルなソリューションが最も美しい。複雑さは敵です ✨",
    "バグは学習の機会。エラーメッセージは先生からのメッセージです。",
    "良いコードは詩のようなもの。読みやすく、美しく、意味がある。",
    "ドキュメントは未来の自分への贈り物。丁寧に書きましょう 📝",
    "オープンソースの精神：共有し、学び、改善し、また共有する。",
    "インターネットの本来の姿は分散型でした。その理想を取り戻そう。",
    "技術は人を幸せにするためのツール。そのことを忘れずにいたい。",
    "テスト完了！全てのシステムが正常に動作しています 🎉"
  ]

  # Mixed language posts
  mixed_posts = [
    "Good morning! おはようございます！Ready for a new day of coding コーディング 💻",
    "Coffee time ☕ コーヒータイム！Perfect fuel for programming プログラミングの燃料",
    "Debug mode activated デバッグモード起動中 🔍 Let's find those bugs!",
    "Open source オープンソース is beautiful 美しい！Sharing knowledge 知識の共有",
    "Hello world! こんにちは世界！#MultiLingual #多言語 #ActivityPub",
    "Coding コーディング in progress... 進行中 Almost done! もうすぐ完成",
    "Technology 技術 brings people together 人々を繋ぐ Across borders 国境を越えて 🌍",
    "Learning 学習 new things 新しいこと every day 毎日 Keep growing! 成長し続けよう",
    "Federation 連合 test テスト successful 成功！International connections 国際的な繋がり",
    "Good code 良いコード speaks all languages すべての言語を話す Universal truth 普遍的真理",
    "Version control バージョン管理 saves lives 命を救う Git is love Git は愛 💝",
    "Documentation ドキュメント is important 重要！Future self 未来の自分 will thank you 感謝する",
    "Community コミュニティ power パワー！Together 一緒に we build 構築する amazing things 素晴らしいもの",
    "Simple シンプル solutions 解決策 are the best 最高！Keep it clean きれいに保つ ✨",
    "Internet インターネット freedom 自由！Decentralized 分散型 is the way 道",
    "Happy coding! 楽しいコーディング！May your builds ビルド always succeed 成功しますように 🚀",
    "Open web オープンウェブ for everyone みんなのために！Access アクセス without barriers 障壁なし",
    "Innovation 革新 happens 起こる when cultures 文化 meet 出会う Diversity 多様性 is strength 力",
    "Testing テスト multilingual 多言語 support サポート Everything works! すべて動作します",
    "Finished! 完了！All tests テスト passed 合格 Ready for production 本番環境準備完了 🎯"
  ]

  def create_posts(posts, category)
    puts "\\nCreating \#{posts.length} \#{category} posts..."
    success_count = 0
    
    posts.each_with_index do |content, index|
      print "  Post \#{index + 1}/\#{posts.length}: "
      
      response = make_api_request('/api/v1/statuses', 'POST', {
        status: content,
        visibility: 'public'
      })
      
      if response && response['id']
        puts "✓ Created (ID: \#{response['id']})"
        success_count += 1
      else
        puts "✗ Failed"
      end
      
      sleep 0.3  # Rate limiting
    end
    
    puts "  \#{category}: \#{success_count}/\#{posts.length} posts created successfully"
    success_count
  end

  # Create all posts
  puts "Starting post creation..."
  
  english_success = create_posts(english_posts, "English")
  japanese_success = create_posts(japanese_posts, "Japanese")
  mixed_success = create_posts(mixed_posts, "Mixed Language")
  
  total_success = english_success + japanese_success + mixed_success
  total_attempted = english_posts.length + japanese_posts.length + mixed_posts.length
  
  puts "\\n=== Summary ==="
  puts "English posts: \#{english_success}/\#{english_posts.length}"
  puts "Japanese posts: \#{japanese_success}/\#{japanese_posts.length}"
  puts "Mixed posts: \#{mixed_success}/\#{mixed_posts.length}"
  puts "Total: \#{total_success}/\#{total_attempted} posts created"
  puts "Success rate: \#{(total_success.to_f / total_attempted * 100).round(1)}%"

rescue => e
  puts "✗ Error: \#{e.message}"
  exit 1
end
EOF

# スクリプト実行
rails runner tmp_create_posts.rb

# 一時ファイルの削除
rm -f tmp_create_posts.rb