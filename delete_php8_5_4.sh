#!/bin/bash
# PHP 8.5.4 설치 정리 스크립트
# 제거 대상:
#   - 설치 디렉토리: /usr/local/php
#   - 소스 디렉토리: /usr/local/src/php-build
#   - 다운로드 파일: /tmp/php-8.5.4.tar.gz
#   - PHP 에러 로그: /var/log/php_errors.log
#   - httpd.conf 에 추가된 PHP 핸들러 블록
#   - httpd.conf DirectoryIndex 의 index.php 항목

print_shell() { echo "[$(date +"%Y-%m-%d %H:%M:%S")] $@"; }

print_shell "===== PHP 8.5.4 정리 시작: $(date) ====="

# root 권한 확인
if [ "$(id -u)" -ne 0 ]; then
    print_shell "오류: root 권한으로 실행하세요."
    exit 1
fi

INSTALL_DIR="/usr/local/php"
SOURCE_DIR="/usr/local/src/php-build"
PHP_TAR="php-8.5.4.tar.gz"
HTTPD_CONF="/usr/local/apache2/conf/httpd.conf"

if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    print_shell "PHP 설치 디렉토리 제거 완료: $INSTALL_DIR"
else
    print_shell "PHP 설치 디렉토리 없음 (스킵): $INSTALL_DIR"
fi

if [ -d "$SOURCE_DIR" ]; then
    rm -rf "$SOURCE_DIR"
    print_shell "소스 디렉토리 제거 완료: $SOURCE_DIR"
else
    print_shell "소스 디렉토리 없음 (스킵): $SOURCE_DIR"
fi

if [ -f "/tmp/$PHP_TAR" ]; then
    rm -f "/tmp/$PHP_TAR"
    print_shell "다운로드 파일 제거 완료: /tmp/$PHP_TAR"
else
    print_shell "다운로드 파일 없음 (스킵): /tmp/$PHP_TAR"
fi

if [ -f /var/log/php_errors.log ]; then
    rm -f /var/log/php_errors.log
    print_shell "/var/log/php_errors.log 제거 완료"
else
    print_shell "/var/log/php_errors.log 없음 (스킵)"
fi

if [ -f "$HTTPD_CONF" ]; then
    if grep -q "libphp" "$HTTPD_CONF"; then
        sed -i '/libphp/d' "$HTTPD_CONF"
        print_shell "httpd.conf libphp LoadModule 라인 제거 완료"
    else
        print_shell "httpd.conf libphp 라인 없음 (스킵)"
    fi

    if grep -q "application/x-httpd-php" "$HTTPD_CONF"; then
        START_LINE=$(grep -n "# PHP 연동 설정" "$HTTPD_CONF" | head -1 | cut -d: -f1)
        END_LINE=$(grep -n "AddType application/x-httpd-php-source" "$HTTPD_CONF" | tail -1 | cut -d: -f1)
        if [ -n "$START_LINE" ] && [ -n "$END_LINE" ]; then
            BLANK_LINE=$((START_LINE - 1))
            if [ "$(sed -n "${BLANK_LINE}p" "$HTTPD_CONF")" = "" ]; then
                sed -i "${BLANK_LINE},${END_LINE}d" "$HTTPD_CONF"
            else
                sed -i "${START_LINE},${END_LINE}d" "$HTTPD_CONF"
            fi
            print_shell "httpd.conf PHP 핸들러 블록 제거 완료"
        fi
    else
        print_shell "httpd.conf PHP 핸들러 블록 없음 (스킵)"
    fi

    if grep -q "DirectoryIndex.*index\.php" "$HTTPD_CONF"; then
        sed -i "s| index\.php||g" "$HTTPD_CONF"
        print_shell "httpd.conf DirectoryIndex index.php 제거 완료"
    else
        print_shell "httpd.conf DirectoryIndex index.php 없음 (스킵)"
    fi

    # Apache 설정 문법 검사
    if [ -f /usr/local/apache2/bin/httpd ]; then
        /usr/local/apache2/bin/httpd -t
        print_shell "Apache 설정 문법 검사 완료"
    fi
else
    print_shell "httpd.conf 없음 (스킵): $HTTPD_CONF"
fi

if systemctl is-active httpd &>/dev/null; then
    systemctl restart httpd
    print_shell "Apache 재시작 완료 (PHP 모듈 언로드)"
fi

print_shell "===== PHP 8.5.4 정리 완료: $(date) ====="
