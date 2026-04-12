#!/bin/bash
# WordPress 6.9.4 설치 정리 스크립트
# 제거 대상:
#   - WordPress 웹루트: /usr/local/apache2/htdocs/wordpress
#   - 소스 디렉토리: /usr/local/src/wordpress-build
#   - 다운로드 파일: /tmp/wordpress-6.9.4.tar.gz
#   - httpd.conf 에 추가된 WordPress Directory 블록

print_shell() { echo "[$(date +"%Y-%m-%d %H:%M:%S")] $@"; }

print_shell "===== WordPress 6.9.4 정리 시작: $(date) ====="

# root 권한 확인
if [ "$(id -u)" -ne 0 ]; then
    print_shell "오류: root 권한으로 실행하세요."
    exit 1
fi

INSTALL_DIR="/usr/local/apache2/htdocs/wordpress"
SOURCE_DIR="/usr/local/src/wordpress-build"
WORDPRESS_TAR="wordpress-6.9.4.tar.gz"
HTTPD_CONF="/usr/local/apache2/conf/httpd.conf"

# ─────────────────────────────────────────────
# 1. WordPress 웹루트 제거
# ─────────────────────────────────────────────
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    print_shell "WordPress 웹루트 제거 완료: $INSTALL_DIR"
else
    print_shell "WordPress 웹루트 없음 (스킵): $INSTALL_DIR"
fi

# ─────────────────────────────────────────────
# 2. 소스 디렉토리 제거
# ─────────────────────────────────────────────
if [ -d "$SOURCE_DIR" ]; then
    rm -rf "$SOURCE_DIR"
    print_shell "소스 디렉토리 제거 완료: $SOURCE_DIR"
else
    print_shell "소스 디렉토리 없음 (스킵): $SOURCE_DIR"
fi

# ─────────────────────────────────────────────
# 3. 다운로드 파일 제거
# ─────────────────────────────────────────────
if [ -f "/tmp/$WORDPRESS_TAR" ]; then
    rm -f "/tmp/$WORDPRESS_TAR"
    print_shell "다운로드 파일 제거 완료: /tmp/$WORDPRESS_TAR"
else
    print_shell "다운로드 파일 없음 (스킵): /tmp/$WORDPRESS_TAR"
fi

# ─────────────────────────────────────────────
# 4. httpd.conf WordPress Directory 블록 제거
# ─────────────────────────────────────────────
if [ -f "$HTTPD_CONF" ] && grep -q "htdocs/wordpress" "$HTTPD_CONF"; then
    # "# WordPress 디렉토리 설정" 빈 줄 포함 ~ </Directory> 까지 제거
    sed -i '/^$/{ N; /\n# WordPress 디렉토리 설정/{
        :loop
        N
        /<\/Directory>/!b loop
        d
    }}' "$HTTPD_CONF"

    # 위 패턴으로 못 지워진 경우 대비: 직접 블록 탐색 후 제거
    if grep -q "htdocs/wordpress" "$HTTPD_CONF"; then
        START_LINE=$(grep -n "# WordPress 디렉토리 설정" "$HTTPD_CONF" | head -1 | cut -d: -f1)
        END_LINE=$(awk "NR>=${START_LINE:-0} && /<\/Directory>/{print NR; exit}" "$HTTPD_CONF")
        if [ -n "$START_LINE" ] && [ -n "$END_LINE" ]; then
            # 블록 앞 빈 줄도 함께 제거
            BLANK_LINE=$((START_LINE - 1))
            if [ "$(sed -n "${BLANK_LINE}p" "$HTTPD_CONF")" = "" ]; then
                sed -i "${BLANK_LINE},${END_LINE}d" "$HTTPD_CONF"
            else
                sed -i "${START_LINE},${END_LINE}d" "$HTTPD_CONF"
            fi
        fi
    fi
    print_shell "httpd.conf WordPress Directory 블록 제거 완료"
else
    print_shell "httpd.conf WordPress 설정 없음 (스킵)"
fi

print_shell "===== WordPress 6.9.4 정리 완료: $(date) ====="
