#!/bin/bash
# 소스 압축 파일은 /tmp에 저장
# 소스 파일은 /usr/local/src/wordpress-build 디렉토리에 압축 해제
# 설치 경로: /usr/local/apache2/htdocs/wordpress

# 로그 설정
mkdir -p ./log
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="./log/wordpress_install_6_9_4_${TIMESTAMP}.log"
ERROR_LOG_FILE="./log/wordpress_install_6_9_4_error_${TIMESTAMP}.log"
exec 3>&1               # fd3 = 터미널
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush() }' >> "$LOG_FILE") \
     2> >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush() }' >> "$ERROR_LOG_FILE")
print_shell() {
    local msg="[$(date +"%Y-%m-%d %H:%M:%S")] $@"
    echo "$msg" >&3
    echo "$msg" >> "$LOG_FILE"
}
print_shell "===== WordPress 6.9.4 설치 시작: $(date) ====="

# 변수 설정
WORDPRESS_DOWNLOAD_URL="https://wordpress.org/wordpress-6.9.4.tar.gz"
WORDPRESS_TAR="wordpress-6.9.4.tar.gz"
WORDPRESS_DIR="wordpress"
WORDPRESS_SHA1="018542f4c3e15db0d8e38aaf0fcf1b5dc56dbb79"
SOURCE_DIR="/usr/local/src/wordpress-build"
INSTALL_DIR="/usr/local/apache2/htdocs/wordpress"
APACHE_DIR="/usr/local/apache2"

# 데이터베이스 설정
DB_NAME="${DB_NAME:-wordpressDB}"
DB_USER="${DB_USER:-wordpressuser}"
DB_PASSWORD="${DB_PASSWORD:-1212}"
DB_HOST="${DB_HOST:-192.168.0.244}"
DB_CHARSET="utf8mb4"
DB_COLLATE="utf8mb4_unicode_ci"
TABLE_PREFIX="${TABLE_PREFIX:-blog_}"

print_shell "DB 연결 대상: $DB_HOST (환경변수로 변경 가능)"

# WordPress 중복 설치 체크
if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/index.php" ]; then
    print_shell "WordPress가 이미 설치되어 있습니다: $INSTALL_DIR"
    print_shell "설치를 중단합니다. 재설치 시 $INSTALL_DIR 디렉토리를 삭제 후 실행하세요."
    exit 0
fi

# Apache 설치 확인
if [ ! -d "$APACHE_DIR" ] || [ ! -f "$APACHE_DIR/bin/httpd" ]; then
    print_shell "오류: Apache를 찾을 수 없습니다: $APACHE_DIR/bin/httpd"
    print_shell "Apache를 먼저 설치하세요 (install_source_apache2_4_66.sh)."
    exit 1
fi

# mod_rewrite 활성화 확인
HTTPD_CONF="$APACHE_DIR/conf/httpd.conf"
if ! grep -q "LoadModule rewrite_module" "$HTTPD_CONF"; then
    print_shell "오류: Apache mod_rewrite가 활성화되지 않았습니다."
    print_shell "httpd.conf 에서 LoadModule rewrite_module 주석을 해제하세요."
    exit 1
fi

# AllowOverride All 경고
if ! grep -q "AllowOverride All" "$HTTPD_CONF"; then
    print_shell "경고: httpd.conf 에 AllowOverride All 설정이 없습니다."
    print_shell ".htaccess 가 적용되지 않을 수 있습니다. 설치 후 확인하세요."
fi

print_shell "설치 전 검사 완료"

if [ ! -f "/tmp/$WORDPRESS_TAR" ]; then
    wget -P /tmp "$WORDPRESS_DOWNLOAD_URL"
    if [ $? -ne 0 ]; then
        print_shell "오류: WordPress 다운로드 실패"
        exit 1
    fi
else
    print_shell "이미 다운로드된 파일 존재: /tmp/$WORDPRESS_TAR"
fi
print_shell "WordPress 소스 코드 다운로드 완료"

# 무결성 검증 (SHA1)
print_shell "WordPress 소스 코드 무결성 검증 시작"
ACTUAL_SHA1=$(sha1sum "/tmp/$WORDPRESS_TAR" | awk '{print $1}')
if [ "$WORDPRESS_SHA1" != "$ACTUAL_SHA1" ]; then
    print_shell "무결성 검증 실패: SHA1 불일치"
    print_shell "  예상값: $WORDPRESS_SHA1"
    print_shell "  실제값: $ACTUAL_SHA1"
    exit 1
fi
print_shell "WordPress 소스 코드 무결성 검증 완료"

mkdir -p "$SOURCE_DIR"
tar -xzf "/tmp/$WORDPRESS_TAR" -C "$SOURCE_DIR/"
print_shell "WordPress 소스 코드 압축 해제 완료: $SOURCE_DIR/$WORDPRESS_DIR"

# Apache 웹루트 존재 확인
HTDOCS_DIR="$APACHE_DIR/htdocs"
if [ ! -d "$HTDOCS_DIR" ]; then
    print_shell "오류: Apache 웹루트 디렉토리가 없습니다: $HTDOCS_DIR"
    exit 1
fi

print_shell "WordPress 파일을 Apache 웹루트로 복사 시작: $INSTALL_DIR"
cp -r "$SOURCE_DIR/$WORDPRESS_DIR" "$HTDOCS_DIR/"
print_shell "WordPress 파일 복사 완료: $INSTALL_DIR"

print_shell "wp-config.php 생성 시작"
cp "$INSTALL_DIR/wp-config-sample.php" "$INSTALL_DIR/wp-config.php"
if [ ! -f "$INSTALL_DIR/wp-config.php" ]; then
    print_shell "오류: wp-config.php 생성 실패"
    exit 1
fi

# 데이터베이스 설정 치환
sed -i \
    -e "s|define( 'DB_NAME', 'database_name_here' );|define( 'DB_NAME', '$DB_NAME' );|" \
    -e "s|define( 'DB_USER', 'username_here' );|define( 'DB_USER', '$DB_USER' );|" \
    -e "s|define( 'DB_PASSWORD', 'password_here' );|define( 'DB_PASSWORD', '$DB_PASSWORD' );|" \
    -e "s|define( 'DB_HOST', 'localhost' );|define( 'DB_HOST', '$DB_HOST' );|" \
    -e "s|define( 'DB_CHARSET', 'utf8' );|define( 'DB_CHARSET', '$DB_CHARSET' );|" \
    "$INSTALL_DIR/wp-config.php"

# DB_COLLATE 설정 (기본값이 빈 문자열이므로 별도 처리)
sed -i "s|define( 'DB_COLLATE', '' );|define( 'DB_COLLATE', '$DB_COLLATE' );|" \
    "$INSTALL_DIR/wp-config.php"

# 테이블 프리픽스 설정
sed -i "s|^\$table_prefix = 'wp_';|\$table_prefix = '$TABLE_PREFIX';|" \
    "$INSTALL_DIR/wp-config.php"

print_shell "wp-config.php DB 설정 완료"
print_shell "  DB_NAME=$DB_NAME / DB_USER=$DB_USER / DB_HOST=$DB_HOST / TABLE_PREFIX=$TABLE_PREFIX"

print_shell "WordPress 보안 키/솔트 생성 시작"
SALT_DATA=$(wget -q -O - "https://api.wordpress.org/secret-key/1.1/salt/" 2>/dev/null)

if [ -n "$SALT_DATA" ]; then
    START_LINE=$(grep -n "define( 'AUTH_KEY'" "$INSTALL_DIR/wp-config.php" | head -1 | cut -d: -f1)
    END_LINE=$(sed -n "/define( 'NONCE_SALT'/=" "$INSTALL_DIR/wp-config.php" | tail -1)


    if [ -n "$START_LINE" ] && [ -n "$END_LINE" ]; then
        # 기존 키/솔트 라인 삭제 후 새 데이터 삽입
        sed -i "${START_LINE},${END_LINE}d" "$INSTALL_DIR/wp-config.php"

        # API 응답을 줄 단위로 배열에 저장
        mapfile -t SALT_LINES <<< "$SALT_DATA"

        # 삭제한 위치(START_LINE)부터 한 줄씩 순서대로 삽입
        INSERT_LINE=$((START_LINE - 1))
        for line in "${SALT_LINES[@]}"; do
            # sed 특수문자( / 와 & ) 이스케이프 처리 후 INSERT_LINE 다음 줄에 삽입
            ESCAPED=$(echo "$line" | sed 's/[\/&]/\\&/g')
            sed -i "${INSERT_LINE}a\\${ESCAPED}" "$INSTALL_DIR/wp-config.php"
            INSERT_LINE=$((INSERT_LINE + 1))
        done
        print_shell "보안 키/솔트 자동 생성 및 적용 완료"
    else
        print_shell "경고: wp-config.php 에서 키/솔트 위치를 찾지 못했습니다. 수동 설정이 필요합니다."
        print_shell "  참고: https://api.wordpress.org/secret-key/1.1/salt/"
    fi
else
    print_shell "경고: 보안 키/솔트 API 호출 실패 (네트워크 확인). 기본값을 유지합니다."
    print_shell "  보안 강화를 위해 나중에 수동으로 설정하세요: https://api.wordpress.org/secret-key/1.1/salt/"
fi

print_shell "WordPress 파일 권한 설정 시작"

# 소유자를 apache:apache 로 변경
chown -R apache:apache "$INSTALL_DIR"
print_shell "소유자 변경 완료: apache:apache"

# 디렉토리 권한: u=rwx,g=rx,o=rx
find "$INSTALL_DIR" -type d -exec chmod u=rwx,g=rx,o=rx {} \;
print_shell "디렉토리 권한 설정 완료: u=rwx,g=rx,o=rx"

# 파일 권한: u=rw,g=r,o=r
find "$INSTALL_DIR" -type f -exec chmod u=rw,g=r,o=r {} \;
print_shell "파일 권한 설정 완료: u=rw,g=r,o=r"

# wp-config.php 권한 강화: u=rw,g=,o= (소유자만 읽기/쓰기)
chmod u=rw,g=,o= "$INSTALL_DIR/wp-config.php"
print_shell "wp-config.php 권한 강화 완료: u=rw,g=,o="

# wp-content 쓰기 권한: u=rwx,g=rx,o=rx (플러그인/테마/업로드 파일 저장)
chmod u=rwx,g=rx,o=rx "$INSTALL_DIR/wp-content"
chown -R apache:apache "$INSTALL_DIR/wp-content"
print_shell "wp-content 권한 설정 완료: u=rwx,g=rx,o=rx"

print_shell "WordPress 파일 권한 설정 완료"

print_shell "httpd.conf WordPress 설정 시작"

# DocumentRoot를 wordpress 디렉토리로 변경 (http://서버IP/ 로 바로 접속)
if grep -q "DocumentRoot \"$APACHE_DIR/htdocs\"" "$HTTPD_CONF"; then
    sed -i "s|DocumentRoot \"$APACHE_DIR/htdocs\"|DocumentRoot \"$INSTALL_DIR\"|" "$HTTPD_CONF"
    sed -i "s|<Directory \"$APACHE_DIR/htdocs\">|<Directory \"$INSTALL_DIR\">|" "$HTTPD_CONF"
    print_shell "DocumentRoot 변경 완료: $INSTALL_DIR"
else
    print_shell "DocumentRoot 이미 변경됨 (스킵)"
fi

# wordpress 디렉토리 블록 중복 확인
if ! grep -q "htdocs/wordpress" "$HTTPD_CONF"; then
    cat << APACHEEOF >> "$HTTPD_CONF"

# WordPress 디렉토리 설정
<Directory "$INSTALL_DIR">
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
APACHEEOF
    print_shell "WordPress 디렉토리 블록 추가 완료 (AllowOverride All)"
else
    print_shell "WordPress 디렉토리 설정 이미 존재, 스킵"
fi

print_shell "httpd.conf WordPress 설정 완료"

print_shell ".htaccess 파일 생성 시작"

cat << 'HTACCESSEOF' > "$INSTALL_DIR/.htaccess"
# BEGIN WordPress
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteBase /
    RewriteRule ^index\.php$ - [L]
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTACCESSEOF

if [ $? -eq 0 ]; then
    chmod 644 "$INSTALL_DIR/.htaccess"
    chown apache:apache "$INSTALL_DIR/.htaccess"
    print_shell ".htaccess 파일 생성 완료"
else
    print_shell "오류: .htaccess 파일 생성 실패"
    exit 1
fi

print_shell "===== WordPress 6.9.4 설치 완료: $(date) ====="
print_shell ""
print_shell "[ 웹 설치 절차 ]"
print_shell "  1. 브라우저에서 접속: http://서버IP/"
print_shell "  2. 언어 선택: 한국어"
print_shell "  3. 데이터베이스 연결 확인 (wp-config.php 설정이 올바르면 자동 통과)"
print_shell "  4. 사이트 정보 입력 (제목, 관리자 계정, 이메일)"
print_shell "  5. 설치 완료 후 관리자 페이지: http://서버IP/wp-admin/"
print_shell ""
print_shell "[ MySQL 연결 정보 ]"
print_shell "  DB_NAME     : $DB_NAME"
print_shell "  DB_USER     : $DB_USER"
print_shell "  DB_HOST     : $DB_HOST"
print_shell "  TABLE_PREFIX: $TABLE_PREFIX"
