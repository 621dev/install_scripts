#!/bin/bash
# Apache 2.4.66 설치 및 소스 파일 정리 스크립트
# 제거 대상:
#   - 서비스: httpd.service
#   - 설치 디렉토리: /usr/local/apache2
#   - 소스 디렉토리: /usr/local/src/apache-build
#   - nghttp2 소스 디렉토리: /usr/local/src/nghttp2-build
#   - 다운로드 파일: /tmp/httpd-*, /tmp/apr-*, /tmp/nghttp2-*
#   - 환경변수 설정: /etc/profile.d/apache.sh
#   - systemd 서비스: /etc/systemd/system/httpd.service
#   - 계정/그룹: apache

print_shell() { echo "[$(date +"%Y-%m-%d %H:%M:%S")] $@"; }

print_shell "===== Apache 2.4.66 정리 시작: $(date) ====="

# root 권한 확인
if [ "$(id -u)" -ne 0 ]; then
    print_shell "오류: root 권한으로 실행하세요."
    exit 1
fi

# 서비스 중지 및 비활성화
if systemctl is-active httpd &>/dev/null; then
    print_shell "httpd 서비스 중지"
    systemctl stop httpd
fi
if systemctl is-enabled httpd &>/dev/null; then
    print_shell "httpd 서비스 비활성화"
    systemctl disable httpd
fi

# systemd 서비스 파일 제거
if [ -f /etc/systemd/system/httpd.service ]; then
    rm -f /etc/systemd/system/httpd.service
    systemctl daemon-reload
    print_shell "httpd.service 제거 완료"
fi

# 설치 디렉토리 제거
if [ -d /usr/local/apache2 ]; then
    rm -rf /usr/local/apache2
    print_shell "/usr/local/apache2 제거 완료"
fi

# 소스 디렉토리 제거
if [ -d /usr/local/src/apache-build ]; then
    rm -rf /usr/local/src/apache-build
    print_shell "/usr/local/src/apache-build 제거 완료"
fi

if [ -d /usr/local/src/nghttp2-build ]; then
    rm -rf /usr/local/src/nghttp2-build
    print_shell "/usr/local/src/nghttp2-build 제거 완료"
fi

# 다운로드 파일 제거
for pattern in "httpd-*.tar.gz" "httpd-*.tar.gz.sha256" "apr-*.tar.gz" "apr-util-*.tar.gz" "nghttp2-*.tar.gz"; do
    for f in /tmp/$pattern; do
        if [ -f "$f" ]; then
            rm -f "$f"
            print_shell "/tmp/$(basename $f) 제거 완료"
        fi
    done
done

# 환경변수 설정 파일 제거
if [ -f /etc/profile.d/apache.sh ]; then
    rm -f /etc/profile.d/apache.sh
    print_shell "/etc/profile.d/apache.sh 제거 완료"
fi

# apache 계정/그룹 제거
if id -u apache &>/dev/null; then
    userdel apache
    print_shell "apache 계정 제거 완료"
fi
if getent group apache &>/dev/null; then
    groupdel apache
    print_shell "apache 그룹 제거 완료"
fi

# 방화벽 포트 제거
if firewall-cmd --state &>/dev/null; then
    for PORT in 80 443; do
        if firewall-cmd --query-port="${PORT}/tcp" --quiet; then
            firewall-cmd --permanent --remove-port="${PORT}/tcp"
            print_shell "방화벽: ${PORT}/tcp 제거 완료"
        fi
    done
    firewall-cmd --reload
fi

print_shell "===== Apache 2.4.66 정리 완료: $(date) ====="
