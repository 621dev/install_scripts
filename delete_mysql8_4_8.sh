#!/bin/bash
# MySQL 8.4.8 설치 정리 스크립트
# 제거 대상:
#   - 서비스: mysqld.service
#   - 설치 디렉토리: /usr/local/mysql
#   - 소스 디렉토리: /usr/local/src/mysql-build
#   - 데이터 디렉토리: /var/lib/mysql
#   - 로그 디렉토리: /var/log/mysqld
#   - PID 디렉토리: /var/run/mysqld
#   - 설정 파일: /etc/my.cnf
#   - 환경변수 설정: /etc/profile.d/mysql.sh
#   - systemd 서비스: /etc/systemd/system/mysqld.service
#   - 다운로드 파일: /tmp/mysql-8.4.8.tar.gz
#   - 계정/그룹: mysql

print_shell() { echo "[$(date +"%Y-%m-%d %H:%M:%S")] $@"; }

print_shell "===== MySQL 8.4.8 정리 시작: $(date) ====="

# root 권한 확인
if [ "$(id -u)" -ne 0 ]; then
    print_shell "오류: root 권한으로 실행하세요."
    exit 1
fi

# ─────────────────────────────────────────────
# 1. 서비스 중지 및 비활성화
# ─────────────────────────────────────────────
if systemctl is-active mysqld &>/dev/null; then
    print_shell "mysqld 서비스 중지"
    systemctl stop mysqld
fi
if systemctl is-enabled mysqld &>/dev/null; then
    print_shell "mysqld 서비스 비활성화"
    systemctl disable mysqld
fi

# ─────────────────────────────────────────────
# 2. systemd 서비스 파일 제거
# ─────────────────────────────────────────────
if [ -f /etc/systemd/system/mysqld.service ]; then
    rm -f /etc/systemd/system/mysqld.service
    systemctl daemon-reload
    print_shell "mysqld.service 제거 완료"
else
    print_shell "mysqld.service 없음 (스킵)"
fi

# ─────────────────────────────────────────────
# 3. 설치 디렉토리 제거
# ─────────────────────────────────────────────
if [ -d /usr/local/mysql ]; then
    rm -rf /usr/local/mysql
    print_shell "/usr/local/mysql 제거 완료"
else
    print_shell "/usr/local/mysql 없음 (스킵)"
fi

# ─────────────────────────────────────────────
# 4. 소스 디렉토리 제거
# ─────────────────────────────────────────────
if [ -d /usr/local/src/mysql-build ]; then
    rm -rf /usr/local/src/mysql-build
    print_shell "/usr/local/src/mysql-build 제거 완료"
else
    print_shell "/usr/local/src/mysql-build 없음 (스킵)"
fi

# ─────────────────────────────────────────────
# 5. 데이터/로그/PID 디렉토리 제거
# ─────────────────────────────────────────────
for dir in /var/lib/mysql /var/log/mysqld /var/run/mysqld; do
    if [ -d "$dir" ]; then
        rm -rf "$dir"
        print_shell "$dir 제거 완료"
    else
        print_shell "$dir 없음 (스킵)"
    fi
done

# ─────────────────────────────────────────────
# 6. 설정 파일 제거
# ─────────────────────────────────────────────
if [ -f /etc/my.cnf ]; then
    rm -f /etc/my.cnf
    print_shell "/etc/my.cnf 제거 완료"
else
    print_shell "/etc/my.cnf 없음 (스킵)"
fi

# ─────────────────────────────────────────────
# 7. 환경변수 설정 파일 제거
# ─────────────────────────────────────────────
if [ -f /etc/profile.d/mysql.sh ]; then
    rm -f /etc/profile.d/mysql.sh
    print_shell "/etc/profile.d/mysql.sh 제거 완료"
else
    print_shell "/etc/profile.d/mysql.sh 없음 (스킵)"
fi

# ─────────────────────────────────────────────
# 8. 다운로드 파일 제거
# ─────────────────────────────────────────────
if [ -f /tmp/mysql-8.4.8.tar.gz ]; then
    rm -f /tmp/mysql-8.4.8.tar.gz
    print_shell "/tmp/mysql-8.4.8.tar.gz 제거 완료"
else
    print_shell "/tmp/mysql-8.4.8.tar.gz 없음 (스킵)"
fi

# ─────────────────────────────────────────────
# 9. mysql 계정/그룹 제거
# ─────────────────────────────────────────────
if id -u mysql &>/dev/null; then
    userdel mysql
    print_shell "mysql 계정 제거 완료"
else
    print_shell "mysql 계정 없음 (스킵)"
fi
if getent group mysql &>/dev/null; then
    groupdel mysql
    print_shell "mysql 그룹 제거 완료"
else
    print_shell "mysql 그룹 없음 (스킵)"
fi

# ─────────────────────────────────────────────
# 10. 방화벽 포트 제거
# ─────────────────────────────────────────────
if firewall-cmd --state &>/dev/null; then
    if firewall-cmd --query-port=3306/tcp --quiet; then
        firewall-cmd --permanent --remove-port=3306/tcp
        firewall-cmd --reload
        print_shell "방화벽: 3306/tcp 제거 완료"
    else
        print_shell "방화벽: 3306/tcp 규칙 없음 (스킵)"
    fi
else
    print_shell "방화벽: firewalld 미실행, 포트 설정 생략"
fi

print_shell "===== MySQL 8.4.8 정리 완료: $(date) ====="
