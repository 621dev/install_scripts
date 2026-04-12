#!/bin/bash
# 소스 압축 파일은 /tmp에 저장
# 소스 파일은 /usr/local/src/mysql-build 디렉토리에 압축 해제
# 빌드 파일은 /usr/local/src/mysql-build/mysql-8.4.x/build 디렉토리에 생성
# 빌드 및 설치는 /usr/local/mysql에 설치

# 로그 설정
LOG_FILE="mysql_install_8_4_8.log"
exec 3>&1               # fd3 = 터미널
exec >> "$LOG_FILE" 2>&1  # stdout/stderr → 로그 파일만
print_shell() { echo "$@" >&3; }  # 터미널에만 출력하는 함수
print_shell "===== mysql 설치 시작: $(date) ====="

# 변수 설정
PERL_DOWNLOAD_URL="https://www.cpan.org/src/5.0/perl-5.42.2.tar.gz"
MYSQL_DOWNLOAD_URL="https://dev.mysql.com/get/Downloads/MySQL-8.4/mysql-8.4.8.tar.gz"
MYSQL_TAR="mysql-8.4.8.tar.gz"
SOURCE_DIR="/usr/local/src/mysql-build"
INSTALL_DIR="/usr/local/mysql"
SHA256="be9d96cdf87f276952a2cdd960f106b960a8860e46c115ed39c1b5f2e0387a20"

# mysql 설치 체크
if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/bin/mysqld" ]; then
    print_shell "MySQL이 이미 설치되어 있습니다: $INSTALL_DIR"
    print_shell "설치를 중단합니다. 재설치 시 $INSTALL_DIR 디렉토리를 삭제 후 실행하세요."
    exit 0
fi

# EPEL, PowerTools 리포지터리 설치 활성화
print_shell "리포지터리 설정 시작"
dnf install -y epel-release
dnf config-manager --set-enabled powertools
print_shell "리포지터리 설정 완료"

# mysql 의존성 패키지 설치
print_shell "mysql 필요 패키지 설치 시작"
dnf install -y \
    cmake \
    make \
    gcc-c++ \
    openssl-devel \
    bison \
    ncurses-devel \
    ninja-build \
    libzstd-devel \
    lz4-devel \
    libtirpc-devel \
    libtirpc \
    rpcgen \
    wget \
    git
print_shell "mysql 필요 패키지 설치 완료"

# perl 패키지 소스 설치 (perl-5.42.2)
# command -v : PATH에서 실행 가능한 perl 탐색 (rpm -qa는 소스 설치된 perl을 감지 못함)
print_shell "perl 설치 확인"
if command -v perl &>/dev/null; then
    print_shell "perl 이미 설치됨: $(perl -v | head -1)"
else
    print_shell "perl 미설치, 소스 설치 시작"
    wget -P /tmp "$PERL_DOWNLOAD_URL"
    mkdir -p /usr/local/src/perl-build
    tar -xzf /tmp/perl-5.42.2.tar.gz -C /usr/local/src/perl-build
    (cd /usr/local/src/perl-build/perl-5.42.2 && ./Configure -des -Dprefix=/usr/local/perl && make && make install)
    export PATH=/usr/local/perl/bin:$PATH
    print_shell "perl 소스 설치 완료"
fi
print_shell "perl 설치 확인 완료"

# GCC Toolset 12 설치 및 활성화
print_shell "GCC Toolset 12 설치 시작"
dnf install -y gcc-toolset-12
source /opt/rh/gcc-toolset-12/enable
print_shell "GCC Toolset 12 설치 및 활성화 완료: $(gcc --version | head -1)"

# 소스 코드 다운로드
print_shell "mysql 소스 코드 다운로드 시작"
if [ -f "/tmp/$MYSQL_TAR" ]; then
    print_shell "이미 다운로드된 파일 존재: /tmp/$MYSQL_TAR"
else
    wget -P /tmp "$MYSQL_DOWNLOAD_URL"
fi
print_shell "mysql 소스 코드 다운로드 완료"

# mysql 소스 코드 무결성 검증
print_shell "mysql 소스 코드 무결성 검증 시작"
is_sha256=$(sha256sum "/tmp/$MYSQL_TAR" | awk '{print $1}')
if [ "$SHA256" != "$is_sha256" ]; then
    print_shell "무결성 검증 실패: SHA256 불일치"
    print_shell "  예상값: $SHA256"
    print_shell "  실제값: $is_sha256"
    exit 1
fi
print_shell "mysql 소스 코드 무결성 검증 완료"

# 소스코드 압축 해제
# tar -tzf : 압축 해제 없이 목록만 출력, head -1로 첫 줄(최상위 경로), cut으로 폴더명 추출
print_shell "mysql 소스 코드 압축 해제 시작"
mkdir -p "$SOURCE_DIR"
tar -xzf "/tmp/$MYSQL_TAR" -C "$SOURCE_DIR"
BUILD_SOURCE_DIR="$SOURCE_DIR/$(tar -tzf "/tmp/$MYSQL_TAR" | head -1 | cut -d'/' -f1)"
print_shell "mysql 소스 코드 압축 해제 완료: $BUILD_SOURCE_DIR"

# cmake 구성 및 컴파일
print_shell "cmake 구성 시작"
mkdir -p "$BUILD_SOURCE_DIR/build"
cd "$BUILD_SOURCE_DIR/build"
cmake .. \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DMYSQL_DATADIR=/var/lib/mysql \
    -DSYSCONFDIR=/etc \
    -DMYSQL_UNIX_ADDR=/var/lib/mysql/mysql.sock \
    -DMYSQL_TCP_PORT=3306 \
    -DDEFAULT_CHARSET=utf8mb4 \
    -DDEFAULT_COLLATION=utf8mb4_unicode_ci \
    -DWITH_SSL=system \
    -DWITH_ZLIB=bundled \
    -DWITH_LZ4=system \
    -DWITH_ZSTD=system \
    -DWITH_UNIT_TESTS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -G Ninja \
    -DINSTALL_BINDIR=bin \
    -DINSTALL_SBINDIR=sbin
print_shell "cmake 구성 완료"

# 컴파일
print_shell "mysql 컴파일 시작 (코어 수: $(nproc))"
ninja -j$(nproc)
print_shell "mysql 컴파일 완료"

# 설치
print_shell "mysql 설치 시작"
ninja install
print_shell "mysql 설치 완료: $INSTALL_DIR"

# 디렉토리 생성
mkdir -p /var/lib/mysql
mkdir -p /var/log/mysqld
mkdir -p /var/run/mysqld

# 전용 시스템 계정 생성
if ! id -u mysql &>/dev/null; then
    groupadd mysql
    useradd -r -g mysql -s /sbin/nologin -d /var/lib/mysql mysql
    print_shell "mysql 전용 시스템 계정 생성 완료 ( mysql:mysql )"
else
    print_shell "mysql 계정 이미 존재"
fi

# 권한 설정
chown -R mysql:mysql /var/lib/mysql
chown -R mysql:mysql /var/log/mysqld
chown -R mysql:mysql /var/run/mysqld
print_shell "디렉토리 권한 설정 완료"

# my.cnf 설정 파일 작성
print_shell "my.cnf 설정 파일 작성 시작"
cat << 'EOF' > /etc/my.cnf
[mysqld]
# 기본 경로 설정
basedir     = /usr/local/mysql
datadir     = /var/lib/mysql
socket      = /var/lib/mysql/mysql.sock
log-error   = /var/log/mysqld/error.log
pid-file    = /var/run/mysqld/mysqld.pid
port        = 3306
user        = mysql

# 문자셋
character-set-server    = utf8mb4
collation-server        = utf8mb4_general_ci

# InnoDB 설정
innodb_buffer_pool_size         = 4G
innodb_log_file_size            = 256M
innodb_flush_log_at_trx_commit  = 1

# InnoDB 성능 튜닝
innodb_file_per_table           = 1
innodb_flush_method             = fsync
innodb_buffer_pool_instances    = 4

# 연결 설정
max_connections     = 200
max_allowed_packet  = 32M

# 느린 쿼리 로그
slow_query_log      = 1
slow_query_log_file = /var/log/mysqld/slow.log
long_query_time     = 2

# 보안 및 네트워크
skip_name_resolve   = 1
skip_symbolic_links = 1
bind-address        = 0.0.0.0

# 연결 및 쿼리 처리
wait_timeout            = 28800
interactive_timeout     = 28800
tmp_table_size          = 64M
max_heap_table_size     = 64M

[client]
socket                  = /var/lib/mysql/mysql.sock
default_character_set   = utf8mb4

[mysqld_safe]
EOF
print_shell "my.cnf 설정 파일 작성 완료"

# PATH 환경변수 설정
cat << 'EOF' > /etc/profile.d/mysql.sh
export PATH=/usr/local/mysql/bin:/usr/local/mysql/sbin:$PATH
export LD_LIBRARY_PATH=/usr/local/mysql/lib:$LD_LIBRARY_PATH
EOF
source /etc/profile.d/mysql.sh
print_shell "PATH 환경변수 설정 완료"

# 데이터 디렉터리 초기화
print_shell "mysql 데이터 디렉터리 초기화 시작"
"$INSTALL_DIR/sbin/mysqld" \
    --defaults-file=/etc/my.cnf \
    --initialize-insecure \
    --user=mysql
print_shell "mysql 데이터 디렉터리 초기화 완료"
print_shell "  ※ 비밀번호 없이 초기화됨. 설치 후 즉시 root 비밀번호를 설정하세요:"
print_shell "     mysql -u root --skip-password"
print_shell "     ALTER USER 'root'@'localhost' IDENTIFIED BY '새비밀번호';"

# systemd 서비스 파일 작성
print_shell "systemd 서비스 파일 작성 시작"
cat << 'EOF' > /etc/systemd/system/mysqld.service
[Unit]
Description=MySQL 8.4 LTS Database Server
Documentation=http://dev.mysql.com/doc/refman/en/using-systemd.html
After=network.target
After=syslog.target

[Service]
User=mysql
Group=mysql
Type=notify
ExecStart=/usr/local/mysql/sbin/mysqld --defaults-file=/etc/my.cnf
ExecStop=/usr/local/mysql/bin/mysqladmin -u root -S /var/lib/mysql/mysql.sock shutdown
PIDFile=/var/run/mysqld/mysqld.pid
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536
LimitNPROC=65536
TimeoutStartSec=30

# RuntimeDirectory는 /var/run/mysqld 를 서비스 시작 시 자동 생성
RuntimeDirectory=mysqld
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
print_shell "systemd 서비스 파일 작성 완료"

# 방화벽 포트 설정
if firewall-cmd --state &>/dev/null; then
    if ! firewall-cmd --query-port=3306/tcp --quiet; then
        print_shell "방화벽: 3306/tcp 포트 추가"
        firewall-cmd --add-port=3306/tcp --permanent
        firewall-cmd --reload
    else
        print_shell "방화벽: 3306/tcp 이미 허용됨"
    fi
else
    print_shell "방화벽: firewalld 미실행, 포트 설정 생략"
fi

print_shell "===== MySQL 서비스 설치 완료: $(date) ====="
print_shell ""
print_shell "설치 후 작업:"
print_shell "  1. 서비스 시작:    systemctl start mysqld"
print_shell "  2. 서비스 활성화:  systemctl enable mysqld"
print_shell "  3. root 비밀번호 설정: mysql -u root --skip-password"
