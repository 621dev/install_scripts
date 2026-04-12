#!/bin/bash
# 소스 압축 파일은 /tmp에 저장
# 소스 파일은 /usr/local/src/apache-build 디렉토리에 압축 해제
# 설치 경로: /usr/local/apache2

# 로그 설정
LOG_FILE="apache_install_2_4_66.log"
exec 3>&1               # fd3 = 터미널
exec >> "$LOG_FILE" 2>&1  # stdout/stderr → 로그 파일만
print_shell() { echo "$@" >&3; }  # 터미널에만 출력하는 함수
print_shell "===== apache2.4.x 설치 시작: $(date) ====="

# 변수 설정
NGHTTP2_DOWNLOAD_URL="https://github.com/nghttp2/nghttp2/releases/download/v1.68.1/nghttp2-1.68.1.tar.gz"
NGHTTP2_TAR="nghttp2-1.68.1.tar.gz"
NGHTTP2_DIR="nghttp2-1.68.1"
APACHE_DOWNLOAD_URL="https://downloads.apache.org/httpd/httpd-2.4.66.tar.gz"
APACHE_SHA256_URL="https://downloads.apache.org/httpd/httpd-2.4.66.tar.gz.sha256"
APACHE_TAR="httpd-2.4.66.tar.gz"
APACHE_DIR="httpd-2.4.66"
APR_DOWNLOAD_URL="https://downloads.apache.org/apr/apr-1.7.6.tar.gz"
APR_UTIL_DOWNLOAD_URL="https://downloads.apache.org/apr/apr-util-1.6.3.tar.gz"
APR_TAR="apr-1.7.6.tar.gz"
APR_UTIL_TAR="apr-util-1.6.3.tar.gz"
SOURCE_DIR="/usr/local/src/apache-build"
INSTALL_DIR="/usr/local/apache2"

# apache 설치 체크
if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/bin/httpd" ]; then
    print_shell "Apache가 이미 설치되어 있습니다: $INSTALL_DIR"
    print_shell "설치를 중단합니다. 재설치 시 $INSTALL_DIR 디렉토리를 삭제 후 실행하세요."
    exit 0
fi

# # root 권한 확인
# if [ "$(id -u)" -ne 0 ]; then
#     print_shell "오류: 이 스크립트는 root 권한으로 실행해야 합니다."
#     exit 1
# fi

# EPEL, PowerTools 리포지터리 활성화
print_shell "리포지터리 설정 시작"
dnf install -y epel-release
dnf config-manager --set-enabled powertools
print_shell "리포지터리 설정 완료"

# 필수 라이브러리 설치
print_shell "필수 라이브러리 설치 시작"
dnf install -y \
    expat-devel \
    openssl-devel \
    zlib-devel \
    pcre2-devel \
    wget \
    tar \
    gcc \
    gcc-c++ \
    make \
    autoconf \
    libtool \
    brotli-devel
print_shell "필수 라이브러리 설치 완료"

# nghttp2-devel 소스 설치 (HTTP/2 지원)
print_shell "nghttp2 설치 확인"
if ldconfig -p | grep -q "libnghttp2"; then
    print_shell "nghttp2 라이브러리 이미 존재, 설치 생략"
else
    print_shell "nghttp2 미설치, 소스 설치 시작"
    mkdir -p /usr/local/src/nghttp2-build
    wget -P /tmp "$NGHTTP2_DOWNLOAD_URL"
    tar -xzf "/tmp/$NGHTTP2_TAR" -C /usr/local/src/nghttp2-build/
    (cd "/usr/local/src/nghttp2-build/$NGHTTP2_DIR" && \
        ./configure --prefix=/usr && \
        make -j$(nproc) && \
        make install)
    print_shell "nghttp2 소스 설치 완료"
fi

# Apache 소스 다운로드
print_shell "Apache 소스 코드 다운로드 시작"
mkdir -p "$SOURCE_DIR"
wget -P /tmp "$APACHE_DOWNLOAD_URL"
print_shell "Apache 소스 코드 다운로드 완료"

# 무결성 검증 (공식 sha256 파일 사용)
print_shell "Apache 소스 코드 무결성 검증 시작"
wget -q -O "/tmp/${APACHE_TAR}.sha256" "$APACHE_SHA256_URL"
EXPECTED_SHA256=$(awk '{print $1}' "/tmp/${APACHE_TAR}.sha256")
ACTUAL_SHA256=$(sha256sum "/tmp/$APACHE_TAR" | awk '{print $1}')
if [ "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]; then
    print_shell "무결성 검증 실패: SHA256 불일치"
    print_shell "  예상값: $EXPECTED_SHA256"
    print_shell "  실제값: $ACTUAL_SHA256"
    exit 1
fi
print_shell "Apache 소스 코드 무결성 검증 완료"

# 소스코드 압축 해제
print_shell "Apache 소스 코드 압축 해제 시작"
tar -xzf "/tmp/$APACHE_TAR" -C "$SOURCE_DIR/"
BUILD_SOURCE_DIR="$SOURCE_DIR/$APACHE_DIR"
print_shell "Apache 소스 코드 압축 해제 완료: $BUILD_SOURCE_DIR"

# APR / APR-util 다운로드 및 배치 (srclib 방식으로 함께 빌드)
print_shell "APR / APR-util 다운로드 시작"
wget -P /tmp "$APR_DOWNLOAD_URL"
wget -P /tmp "$APR_UTIL_DOWNLOAD_URL"

tar -xzf "/tmp/$APR_TAR"      -C "$BUILD_SOURCE_DIR/srclib/"
tar -xzf "/tmp/$APR_UTIL_TAR" -C "$BUILD_SOURCE_DIR/srclib/"

# srclib 안에서 디렉토리명을 apr, apr-util로 변경
mv "$BUILD_SOURCE_DIR/srclib/apr-1.7.6/"      "$BUILD_SOURCE_DIR/srclib/apr/"
mv "$BUILD_SOURCE_DIR/srclib/apr-util-1.6.3/" "$BUILD_SOURCE_DIR/srclib/apr-util/"
print_shell "APR / APR-util 배치 완료"

# configure (빌드 옵션 구성)
print_shell "configure 시작"
cd "$BUILD_SOURCE_DIR"
./configure \
    --prefix="$INSTALL_DIR" \
    --enable-so \
    --enable-ssl \
    --with-ssl=/usr \
    --enable-rewrite \
    --enable-proxy \
    --enable-proxy-http \
    --enable-proxy-balancer \
    --enable-proxy-ajp \
    --enable-headers \
    --enable-expires \
    --enable-deflate \
    --enable-brotli \
    --enable-http2 \
    --enable-cgi \
    --enable-vhost-alias \
    --enable-mime-magic \
    --enable-log-debug \
    --with-included-apr \
    --with-pcre=/usr \
    --with-mpm=event \
    --enable-mods-shared=most
print_shell "configure 완료"

# 컴파일
print_shell "Apache 컴파일 시작 (코어 수: $(nproc))"
make -j$(nproc)
print_shell "Apache 컴파일 완료"

# 설치
print_shell "Apache 설치 시작"
make install
print_shell "Apache 설치 완료: $INSTALL_DIR"
"$INSTALL_DIR/bin/httpd" -v >&3

# 환경 변수 등록
cat << 'EOF' > /etc/profile.d/apache.sh
export APACHE_HOME=/usr/local/apache2
export PATH=$APACHE_HOME/bin:$PATH
EOF
source /etc/profile.d/apache.sh
print_shell "환경 변수 등록 완료"

# 전용 시스템 계정 및 그룹 생성, 권한 부여
if ! id -u apache &>/dev/null; then
    groupadd -r apache
    useradd -r -g apache -s /sbin/nologin -d "$INSTALL_DIR" -c "Apache HTTP Server" apache
    print_shell "apache 전용 시스템 계정 생성 완료 ( apache:apache )"
else
    print_shell "apache 계정 이미 존재"
fi
chown -R apache:apache "$INSTALL_DIR/logs"
print_shell "logs 디렉토리 권한 설정 완료"

# httpd.conf 기본 설정 수정
print_shell "httpd.conf 기본 설정 수정 시작"
HTTPD_CONF="$INSTALL_DIR/conf/httpd.conf"
mkdir -p "$INSTALL_DIR/conf/sample"
cp "$HTTPD_CONF" "$INSTALL_DIR/conf/sample/httpd.conf.bak"

# 실행 계정 / 관리자 설정
sed -i \
    -e "s|^User .*|User apache|" \
    -e "s|^Group .*|Group apache|" \
    -e "s|^ServerAdmin .*|ServerAdmin admin@example.com|" \
    "$HTTPD_CONF"

# PidFile 설정 (PidFile 지시자가 없으면 추가)
if grep -q "^PidFile" "$HTTPD_CONF"; then
    sed -i "s|^PidFile .*|PidFile $INSTALL_DIR/logs/httpd.pid|" "$HTTPD_CONF"
else
    sed -i "/^ServerRoot/a PidFile $INSTALL_DIR/logs/httpd.pid" "$HTTPD_CONF"
fi
print_shell "httpd.conf 기본 설정 수정 완료"

# SSL 모듈 및 설정 활성화
print_shell "SSL 모듈 활성화 시작"
sed -i \
    -e "s|^#LoadModule ssl_module|LoadModule ssl_module|" \
    -e "s|^#LoadModule socache_shmcb_module|LoadModule socache_shmcb_module|" \
    -e "s|^#LoadModule http2_module|LoadModule http2_module|" \
    -e "s|^#Include conf/extra/httpd-ssl.conf|Include conf/extra/httpd-ssl.conf|" \
    "$HTTPD_CONF"
print_shell "SSL 모듈 활성화 완료"

# 자체 서명 인증서 생성
print_shell "자체 서명 인증서 생성 시작"
mkdir -p "$INSTALL_DIR/conf/ssl"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$INSTALL_DIR/conf/ssl/server.key" \
    -out "$INSTALL_DIR/conf/ssl/server.crt" \
    -subj "/C=KR/ST=Seoul/L=Seoul/O=TestOrg/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
print_shell "자체 서명 인증서 생성 완료"

# ssl.conf 인증서 경로 업데이트
SSL_CONF="$INSTALL_DIR/conf/extra/httpd-ssl.conf"
if [ -f "$SSL_CONF" ]; then
    sed -i \
        -e "s|^SSLCertificateFile .*|SSLCertificateFile $INSTALL_DIR/conf/ssl/server.crt|" \
        -e "s|^SSLCertificateKeyFile .*|SSLCertificateKeyFile $INSTALL_DIR/conf/ssl/server.key|" \
        "$SSL_CONF"
    print_shell "ssl.conf 인증서 경로 업데이트 완료"
fi

# systemd 서비스 파일 작성
print_shell "systemd 서비스 파일 작성 시작"
cat << EOF > /etc/systemd/system/httpd.service
[Unit]
Description=Apache HTTP Server 2.4.66
Documentation=man:httpd(8)
Documentation=man:apachectl(8)
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=notify
PIDFile=$INSTALL_DIR/logs/httpd.pid
ExecStart=$INSTALL_DIR/bin/httpd -D FOREGROUND -k start
ExecReload=$INSTALL_DIR/bin/httpd -k graceful
ExecStop=$INSTALL_DIR/bin/apachectl stop
KillMode=mixed
KillSignal=SIGCONT
PrivateTmp=true
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
print_shell "systemd 서비스 파일 작성 완료"

# 방화벽 포트 설정 (80, 443)
if firewall-cmd --state &>/dev/null; then
    for PORT in 80 443; do
        if ! firewall-cmd --query-port="${PORT}/tcp" --quiet; then
            print_shell "방화벽: ${PORT}/tcp 포트 추가"
            firewall-cmd --permanent --add-port="${PORT}/tcp"
        else
            print_shell "방화벽: ${PORT}/tcp 이미 허용됨"
        fi
    done
    firewall-cmd --reload
else
    print_shell "방화벽: firewalld 미실행, 포트 설정 생략"
fi

print_shell "===== Apache 설치 완료: $(date) ====="
print_shell ""
print_shell "설치 후 작업:"
print_shell "  1. 서비스 시작:    systemctl start httpd"
print_shell "  2. 서비스 활성화:  systemctl enable httpd"
print_shell "  3. 설정 문법 확인: $INSTALL_DIR/bin/httpd -t"
print_shell "  4. 응답 확인:      curl -I http://localhost"
print_shell "  5. HTTPS 확인:     curl -Ik https://localhost"
