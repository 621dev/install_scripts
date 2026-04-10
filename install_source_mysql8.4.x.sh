#!/bin/bash
# 소스 압축 파일은 /tmp에 저장
# 소스 파일은 /usr/local/src/[소스이름]-build 디렉토리에 압축 해제
# 빌드 파일은 /usr/local/src/[소스이름]-build/build 디렉토리에 생성
# 빌드 및 설치는 /usr/local/[소스이름]에 설치

# =====================================================================

# 로그 설정
LOG_FILE="mysql_install_84x.log"
exec 3>&1               # fd3 = 터미널
exec >> "$LOG_FILE" 2>&1  # stdout/stderr → 로그 파일만
print_shell() { "$@" >&3; }  # 터미널에만 출력하는 함수
print_shell "===== mysql 설치 시작: $(date) ====="

# 변수 설정
PERL_DOWNLOAD_URL="https://www.cpan.org/src/5.0/perl-5.42.2.tar.gz"
MYSQL_DOWNLOAD_URL="https://dev.mysql.com/get/Downloads/MySQL-8.4/mysql-8.4.8.tar.gz"
SOURCE_DIR="/usr/local/src/mysql-build"
SHA256="be9d96cdf87f276952a2cdd960f106b960a8860e46c115ed39c1b5f2e0387a20"

# mysql 설치 체크

# EPEL, PowerTools 리포지터리 설치 활성화
dnf install -y epel-release
dnf config-manager --set-enabled powertools

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
	git
print_shell "mysql 필요 패키지 설치 완료"

# perl 패키지 소스 설치 (perl-5.42.2)
print_shell "perl 설치 시작"
if rpm -qa | grep -q "perl"; then
    print_shell "perl already installed: $(rpm -qa | grep 'perl')"
else
    print_shell "perl is not installed"
    wget -P /tmp $PERL_DOWNLOAD_URL
    mkdir -p /usr/local/src/perl-build
    tar -xzf /tmp/perl-5.42.2.tar.gz -C /usr/local/src/perl-build
    (cd /usr/local/src/perl-build/perl-5.42.2 && ./Configure -des -Dprefix=/usr/local/perl && make && make install)
fi
print_shell "perl 설치 완료"

# GCC Toolset 12 설치 및 활성화
dnf install -y gcc-toolset-12
source /opt/rh/gcc-toolset-12/enable
print_shell "GCC Toolset 12 설치 및 활성화"

# 소스 코드 다운로드
wget -P /tmp $MYSQL_DOWNLOAD_URL
print_shell "mysql 소스 코드 다운로드 완료"

# mysql 소스 코드 무결성 검증
is_sha256=$(sha256sum /tmp/mysql-8.4.8.tar.gz | awk '{print $1}')
if [ "$SHA256" != "$is_sha256" ]; then
    print_shell "무결성 검증 실패: SHA256 불일치"
    print_shell "  예상값: $SHA256"
    print_shell "  실제값: $is_sha256"
    exit 1
fi
print_shell "mysql 소스 코드 무결성 검증 완료"

# 소스코드 압축 해제
mkdir -p $SOURCE_DIR
tar -xzf /tmp/mysql-8.4.8.tar.gz -C $SOURCE_DIR
SOURCE_DIR="$SOURCE_DIR/$(tar -tzf /tmp/mysql-8.4.8.tar.gz | head -1 | cut -d'/' -f1)"
print_shell "mysql 소스 코드 압축 해제 완료"

# cmake 구성 및 컴파일
mkdir -p $SOURCE_DIR/build
cd $SOURCE_DIR/build
cmake .. \
    -DCMAKE_INSTALL_PREFIX=/usr/local/mysql \
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
ninja -j$(nproc)
print_shell "mysql 컴파일 완료"

# 설치
ninja install
print_shell "mysql 설치 완료"

mkdir -p /var/lib/mysql
mkdir -p /var/log/mysqld
mkdir -p /var/run/mysqld

# 전용 시스템 계정 생성
groupadd mysql
useradd -r -g mysql -s /sbin/nologin -d /var/lib/mysql mysql
print_shell "mysqsl 전용 시스템 계정 생성 완료 ( mysql:mysql )"

# 권한 설정
chown -R mysql:mysql /var/lib/mysql
chown -R mysql:mysql /var/log/mysqld
chown -R mysql:mysql /var/run/mysqld

# my.cnf 설정 파일 작성
cat << EOF > /etc/my.cnf
[mysqld]    # 서버 설정
## 실행, 포트, 스토리지 엔진 옵션 등

basedir     = /usr/local/mysql
datadir     = /var/lib/mysql
socket      = /var/lib/mysql/mysql.sock   # 클라이언트와 서버가 통신할 때 사용하는 유닉스 소켓 파일
log-error   = /var/log/mysqld/error.log
pid-file    = /var/run/mysqld/mysqld.pid
port        = 3306
user        = mysql

# 문자셋
character-set-server    = utf8mb4
collation-server        = utf8mb4_general_ci

# InnoDB 설정
innodb_buffer_pool_size         = 4G    # 메모리 캐싱
innodb_log_file_size            = 256M  # 트랜잭션 로그 파일 크기
innodb_flush_log_at_trx_commit  = 1     # 트랜잭션 커밋 시 디스크에 쓰기 (안전)

# InnoDB 성능 튜닝
innodb_file_per_table          = 1          # 테이블별 파일 생성
innodb_flush_method             = fsync  # OS의 파일 시스템 캐시를 사용하지 않음 [fsync(기본값), O_DIRECT]
innodb_buffer_pool_instances    = 4         # 버퍼 풀을 여러 개로 분할 [1(기본값), 2, 4, 8]

# 연결 설정
max_connections     = 200
max_allowed_packet  = 32M

# 추가 로그 설정
slow_query_log      = 1                         # 느린 쿼리 로그 활성화
slow_query_log_file = /var/log/mysqld/slow.log   # 느린 쿼리 로그 파일 경로
long_query_time     = 2                         # 느린 쿼리 기준 시간(초)

# 보안 및 네트워크
skip_name_resolve    = 1         # DNS를 거치지않고 IP 기반으로만 접속 처리, 기본값: OFF              
skip_symbolic_links = 1         # 심볼릭 링크를 통한 테이블 접근 차단, 기본값: ON
bind-address        = 0.0.0.0

# 연결 및 쿼리 처리
wait_timeout             = 28800          # 클라이언트 연결 유휴 시간 제한, 기본값: 28800
interactive_timeout      = 28800          # 대화형 클라이언트 연결 유휴 시간 제한, 기본값: 28800
tmp_table_size           = 64M            # 임시 테이블 메모리 제한, 기본값: 16M
max_heap_table_size      = 64M            # 메모리 해시 테이블 크기 제한, 기본값: 16M

[client]    # 클라이언트 설정
## 서버 접속 시 사용 소켓, 문자셋 등 

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
mysqld \
  --defaults-file=/etc/my.cnf \
  --initialize-insecure \
  --user=mysql

# 비밀번호 없이 로그인
# mysql -u root --skip-password
# 접속 후 즉시 비밀번호 설정
# ALTER USER 'root'@'localhost' IDENTIFIED BY '비밀번호';

# systemd 서비스 파일 작성
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
ExecStop=/usr/local/mysql/bin/mysqladmin -u root -S /var/lib/mysql/mysqld.sock shutdown
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

# 방화벽을 on / off 체크하고 포트를 추가
if firewall-cmd --state; then
    if ! firewall-cmd --query-port=3306/tcp; then
        print_shell "3306번 포트가 열려 있지 않습니다. 3306번 포트를 추가합니다."
        firewall-cmd --add-port=3306/tcp --permanent
        firewall-cmd --reload
    fi
fi

print_shell "MYSQL 서비스 설치 완료"