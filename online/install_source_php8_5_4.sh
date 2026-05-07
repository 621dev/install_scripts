#!/bin/bash
# 소스 압축 파일은 /tmp에 저장
# 소스 파일은 /usr/local/src/php-build 디렉토리에 압축 해제
# 설치 경로: /usr/local/php

# 로그 설정
mkdir -p ./log
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="./log/php_install_8_5_4_${TIMESTAMP}.log"
ERROR_LOG_FILE="./log/php_install_8_5_4_error_${TIMESTAMP}.log"
exec 3>&1               # fd3 = 터미널
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush() }' >> "$LOG_FILE") \
     2> >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush() }' >> "$ERROR_LOG_FILE")
print_shell() {
    local msg="[$(date +"%Y-%m-%d %H:%M:%S")] $@"
    echo "$msg" >&3
    echo "$msg" >> "$LOG_FILE"
}
print_shell "===== php8.5.x 설치 시작: $(date) ====="

# 변수 설정
PHP_DOWNLOAD_URL="file:///tmp/php-8.5.4.tar.gz"
PHP_TAR="php-8.5.4.tar.gz"
PHP_DIR="php-8.5.4"
SHA256="4fef7f44eff3c18e329504cb0d3eb30b41cf54e2db05cb4ebe8b78fc37d38ce1"
SOURCE_DIR="/usr/local/src/php-build"
INSTALL_DIR="/usr/local/php"
APACHE_DIR="/usr/local/apache2"
MYSQL_HOST="${MYSQL_HOST:-192.168.0.239}"
MYSQL_PORT="${MYSQL_PORT:-3306}"

# PHP 설치 체크
if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/bin/php" ]; then
    print_shell "PHP가 이미 설치되어 있습니다: $INSTALL_DIR"
    print_shell "설치를 중단합니다. 재설치 시 $INSTALL_DIR 디렉토리를 삭제 후 실행하세요."
    exit 0
fi

# Apache 설치 확인
if [ ! -f "$APACHE_DIR/bin/apxs" ]; then
    print_shell "오류: Apache apxs를 찾을 수 없습니다: $APACHE_DIR/bin/apxs"
    print_shell "Apache를 먼저 설치하세요 (install_source_apache2.4.x.sh)."
    exit 1
fi

print_shell "MySQL 연결 대상: $MYSQL_HOST:$MYSQL_PORT (원격 DB 지원, 환경변수로 변경 가능)"

# EPEL, PowerTools 리포지터리 활성화
print_shell "리포지터리 설정 시작"
dnf install -y epel-release
dnf config-manager --set-enabled powertools
print_shell "리포지터리 설정 완료"

# 의존성 패키지 설치
print_shell "PHP 의존성 패키지 설치 시작"
dnf install -y \
    gcc \
    gcc-c++ \
    make \
    autoconf \
    libxml2-devel \
    openssl-devel \
    re2c \
    sqlite-devel \
    curl-devel \
    libjpeg-devel \
    libpng-devel \
    freetype-devel \
    libzip-devel \
    oniguruma-devel \
    bzip2-devel \
    libxslt-devel \
    wget
print_shell "PHP 의존성 패키지 설치 완료"

# ─────────────────────────────────────────────
# PHP 소스 다운로드
print_shell "PHP 소스 코드 다운로드 시작"
mkdir -p "$SOURCE_DIR"
if [ ! -f "/tmp/$PHP_TAR" ]; then
    wget -P /tmp "$PHP_DOWNLOAD_URL"
else
    print_shell "이미 다운로드된 파일 존재: /tmp/$PHP_TAR"
fi
print_shell "PHP 소스 코드 다운로드 완료"

# 무결성 검증
print_shell "PHP 소스 코드 무결성 검증 시작"
ACTUAL_SHA256=$(sha256sum "/tmp/$PHP_TAR" | awk '{print $1}')
if [ "$SHA256" != "$ACTUAL_SHA256" ]; then
    print_shell "무결성 검증 실패: SHA256 불일치"
    print_shell "  예상값: $SHA256"
    print_shell "  실제값: $ACTUAL_SHA256"
    exit 1
fi
print_shell "PHP 소스 코드 무결성 검증 완료"

# 소스코드 압축 해제
print_shell "PHP 소스 코드 압축 해제 시작"
tar -xzf "/tmp/$PHP_TAR" -C "$SOURCE_DIR/"
BUILD_SOURCE_DIR="$SOURCE_DIR/$PHP_DIR"
print_shell "PHP 소스 코드 압축 해제 완료: $BUILD_SOURCE_DIR"

# configure (빌드 옵션 구성)
print_shell "configure 시작"
cd "$BUILD_SOURCE_DIR"
./configure \
    --prefix="$INSTALL_DIR" \
    --with-apxs2="$APACHE_DIR/bin/apxs" \
    --with-mysqli=mysqlnd \
    --with-pdo-mysql=mysqlnd \
    --with-openssl \
    --with-curl \
    --with-zlib \
    --with-bz2 \
    --with-freetype \
    --with-jpeg \
    --with-xsl \
    --enable-mbstring \
    --enable-gd \
    --enable-bcmath \
    --enable-calendar \
    --enable-exif \
    --enable-ftp \
    --enable-sockets \
    --enable-zip \
    CFLAGS="-fPIE" \
    LDFLAGS="-pie"
print_shell "configure 완료"

# 컴파일 및 설치
print_shell "PHP 컴파일 시작 (코어 수: $(nproc))"
make -j$(nproc)
print_shell "PHP 컴파일 완료"

print_shell "PHP 설치 시작"
make install
print_shell "PHP 설치 완료: $INSTALL_DIR"

# 설치 확인
"$INSTALL_DIR/bin/php" -v >&3

# php.ini 설정 파일 구성
print_shell "php.ini 설정 시작"
mkdir -p "$INSTALL_DIR/lib"
cp "$BUILD_SOURCE_DIR/php.ini-production" "$INSTALL_DIR/lib/php.ini"

# php.ini 주요 값 수정
PHP_INI="$INSTALL_DIR/lib/php.ini"

sed -i \
    -e "s|^;date.timezone =.*|date.timezone = Asia/Seoul|" \
    -e "s|^date.timezone =.*|date.timezone = Asia/Seoul|" \
    -e "s|^upload_max_filesize =.*|upload_max_filesize = 50M|" \
    -e "s|^post_max_size =.*|post_max_size = 50M|" \
    -e "s|^memory_limit =.*|memory_limit = 256M|" \
    -e "s|^max_execution_time =.*|max_execution_time = 300|" \
    -e "s|^;error_log =.*|error_log = /var/log/php_errors.log|" \
    "$PHP_INI"

# MySQL 기본 호스트/포트 설정 (원격 DB 지원)
{
    echo "mysqli.default_host = $MYSQL_HOST"
    echo "mysqli.default_port = $MYSQL_PORT"
    echo "pdo_mysql.default_socket ="
} >> "$PHP_INI"

# OPcache 활성화
sed -i \
    -e "s|^;opcache.enable=.*|opcache.enable=1|" \
    -e "s|^;opcache.memory_consumption=.*|opcache.memory_consumption=128|" \
    -e "s|^;opcache.max_accelerated_files=.*|opcache.max_accelerated_files=10000|" \
    -e "s|^;opcache.revalidate_freq=.*|opcache.revalidate_freq=60|" \
    "$PHP_INI"
print_shell "php.ini 설정 완료: $PHP_INI"

## 환경 변수 등록
# cat << 'EOF' > /etc/profile.d/php.sh
# export PHP_HOME=/usr/local/php
# export PATH=$PHP_HOME/bin:$PHP_HOME/sbin:$PATH
# EOF
# print_shell "환경 변수 등록 완료: /etc/profile.d/php.sh"

# Apache httpd.conf 연동 설정
print_shell "Apache httpd.conf PHP 연동 설정 시작"
HTTPD_CONF="$APACHE_DIR/conf/httpd.conf"

# mod_php 모듈 로드 확인 (configure 시 --with-apxs2로 자동 추가됨)
if ! grep -q "libphp" "$HTTPD_CONF"; then
    print_shell "경고: libphp 모듈이 httpd.conf에 없습니다. 수동 확인이 필요합니다."
fi

# PHP 핸들러 설정 추가 (중복 방지)
if ! grep -q "application/x-httpd-php" "$HTTPD_CONF"; then
    cat << 'APACHEEOF' >> "$HTTPD_CONF"

# PHP 연동 설정
<FilesMatch \.php$>
    SetHandler application/x-httpd-php
</FilesMatch>
AddType application/x-httpd-php .php
AddType application/x-httpd-php-source .phps
APACHEEOF
    print_shell "PHP 핸들러 설정 추가 완료"
else
    print_shell "PHP 핸들러 설정 이미 존재"
fi

# DirectoryIndex에 index.php 추가
if grep -q "DirectoryIndex index.html" "$HTTPD_CONF"; then
    sed -i "s|DirectoryIndex index.html|DirectoryIndex index.php index.html |" "$HTTPD_CONF"
    print_shell "DirectoryIndex에 index.php 추가 완료"
fi

# Apache 설정 문법 검사
"$APACHE_DIR/bin/httpd" -t >&3
print_shell "Apache 설정 문법 검사 완료"

print_shell "===== PHP 설치 완료: $(date) ====="
print_shell " php 버전 확인   : /usr/local/php/bin/php -v"
print_shell " Apache 재시작   : systemctl restart httpd"
