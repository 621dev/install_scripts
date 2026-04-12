#!/bin/bash
# WordPress용 MySQL DB / 유저 생성 스크립트
# MySQL 서버에서 직접 실행하세요.
# 실행 방법: bash setup_mysql_wordpress.sh

print_shell() { echo "[$(date +"%Y-%m-%d %H:%M:%S")] $@"; }

print_shell "===== WordPress MySQL 설정 시작: $(date) ====="

# 변수 설정 (환경변수 오버라이드 지원)
DB_NAME="${DB_NAME:-wordpressDB}"
DB_USER="${DB_USER:-wordpressuser}"
DB_PASSWORD="${DB_PASSWORD:-1212}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-1212}"
DB_CHARSET="utf8mb4"
DB_COLLATE="utf8mb4_unicode_ci"


# mysql 클라이언트 탐색
MYSQL_CMD=""
for candidate in /usr/local/mysql/bin/mysql mysql; do
    if command -v "$candidate" &>/dev/null; then
        MYSQL_CMD="$candidate"
        break
    fi
done

if [ -z "$MYSQL_CMD" ]; then
    print_shell "오류: mysql 클라이언트를 찾을 수 없습니다."
    exit 1
fi

# 접속 옵션 구성
MYSQL_OPTS="-u root -p$DB_ROOT_PASSWORD"

# MySQL 접속 확인
if ! $MYSQL_CMD $MYSQL_OPTS -e "SELECT 1;" &>/dev/null; then
    print_shell "오류: MySQL 접속 실패 (user=root)"
    print_shell "  DB_ROOT_PASSWORD 환경변수를 확인하세요."
    exit 1
fi
print_shell "MySQL 접속 확인 완료"

# DB 생성
DB_EXISTS=$($MYSQL_CMD $MYSQL_OPTS -sse \
    "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB_NAME';" 2>/dev/null)
if [ -z "$DB_EXISTS" ]; then
    $MYSQL_CMD $MYSQL_OPTS -e \
        "CREATE DATABASE \`$DB_NAME\` CHARACTER SET $DB_CHARSET COLLATE $DB_COLLATE;"
    print_shell "DB 생성 완료: $DB_NAME"
else
    print_shell "DB 이미 존재 (스킵): $DB_NAME"
fi


# 유저 생성
USER_EXISTS=$($MYSQL_CMD $MYSQL_OPTS -sse \
    "SELECT User FROM mysql.user WHERE User='$DB_USER' AND Host='%';" 2>/dev/null)
if [ -z "$USER_EXISTS" ]; then
    $MYSQL_CMD $MYSQL_OPTS -e \
        "CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';"
    print_shell "유저 생성 완료: $DB_USER@%"
else
    print_shell "유저 이미 존재 (스킵): $DB_USER@%"
fi

# 권한 부여
$MYSQL_CMD $MYSQL_OPTS -e \
    "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';"
$MYSQL_CMD $MYSQL_OPTS -e "FLUSH PRIVILEGES;"
print_shell "권한 부여 완료: $DB_USER → $DB_NAME"

print_shell "===== WordPress MySQL 설정 완료: $(date) ====="
print_shell ""
print_shell "[ 설정 정보 ]"
print_shell "  DB_NAME : $DB_NAME"
print_shell "  DB_USER : $DB_USER"
print_shell "  DB_HOST : WordPress 서버에서 이 서버 IP를 DB_HOST로 지정하세요."
