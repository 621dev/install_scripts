# 로그 설정
LOG_FILE="apache_install_24x.log"
exec 3>&1               # fd3 = 터미널
exec >> "$LOG_FILE" 2>&1  # stdout/stderr → 로그 파일만
print_shell() { "$@" >&3; }  # 터미널에만 출력하는 함수
print_shell "===== apache2.4.x 설치 시작: $(date) ====="

# 변수 설정
NGHTTP2_DOWNLOAD_URL="https://github.com/nghttp2/nghttp2/releases/download/v1.68.1/nghttp2-1.68.1.tar.gz"
APACHE_DOWNLOAD_URL="https://downloads.apache.org/httpd/httpd-2.4.66.tar.gz"
SOURCE_DIR="/usr/local/src/apache-build"
SHA256="https://downloads.apache.org/httpd/httpd-2.4.66.tar.gz.sha256"
APR="https://downloads.apache.org/apr/apr-1.7.6.tar.gz"
APR_UTIL="https://downloads.apache.org/apr/apr-util-1.6.3.tar.gz"
# apache 설치 체크

# EPEL, PowerTools 리포지터리 설치 활성화
dnf install -y epel-release
dnf config-manager --set-enabled powertools

# 필수 라이브러리 설치
dnf install -y \
	expat-devel \
    openssl-devel \
    zlib-devel \
    pcre2-devel \
    wget tar \
    gcc gcc-c++ make \
    autoconf \
    libtool \
    brotli-devel
print_shell "필수 라이브러리 설치 완료"

# nghttp2-devel 소스 설치
if rpm -qa | grep -q "nghttp2"; then
    print_shell "nghttp2 설치됨 : $(rpm -qa | grep 'nghttp2')"
    print_shell "nghttp2 설치 없이 진행합니다."
else
    print_shell "nghttp2 미설치, 설치 진행합니다."
    wget -P /tmp/ $NGHTTP2_DOWNLOAD_URL
    tar -xzf /tmp/nghttp2-1.68.1.tar.gz -C /usr/local/src/nghttp2-build
    (cd /usr/local/src/nghttp2-build/nghttp2-1.68.1 && ./configure --prefix=/usr/local/nghttp2 && make && make install)
fi
print_shell "nghttp2 설치 완료"

# apache 소스 압축 다운로드
mkdir -p $SOURCE_DIR
wget -P /tmp $APACHE_DOWNLOAD_URL

# 무결성 검증
wget -P /tmp $SHA256
echo "$SHA256  /tmp/httpd-2.4.66.tar.gz" | sha256sum -c - || { print_shell "무결성 검증 실패: SHA256 불일치"; exit 1; }
print_shell "apache 소스 코드 무결성 검증 완료"

# 소스코드 압축 해제
tar -xzf /tmp/httpd-2.4.66.tar.gz -C $SOURCE_DIR
SOURCE_DIR="$SOURCE_DIR/$(tar -tzf /tmp/httpd-2.4.66.tar.gz | head -1 | cut -d'/' -f1)"
mkdir -p $SOURCE_DIR

# APR 소스 다운로드
wget -P /tmp https://downloads.apache.org/apr/apr-1.7.6.tar.gz
wget -P /tmp https://downloads.apache.org/apr/apr-util-1.6.3.tar.gz

tar -xzf /tmp/apr-1.7.6.tar.gz -C $SOURCE_DIR/httpd-2.4.66/srclib/
tar -xzf /tmp/apr-util-1.6.3.tar.gz -C $SOURCE_DIR/httpd-2.4.66/srclib/

mv $SOURCE_DIR/httpd-2.4.66/srclib/apr-1.7.6/ $SOURCE_DIR/httpd-2.4.66/srclib/apr/
mv $SOURCE_DIR/httpd-2.4.66/srclib/apr-util-1.6.3/ $SOURCE_DIR/httpd-2.4.66/srclib/apr-util/

cd $SOURCE_DIR
./configure \
    --prefix=/usr/local/apache2 \
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
make -j$(nproc)
print_shell "apache 컴파일 완료"

# 설치
make install

# 환경 변수 등록
touch /etc/profile.d/apache.sh
cat > /etc/profile.d/apache.sh << 'EOF'
export APACHE_HOME=/usr/local/apache2
export PATH=$APACHE_HOME/bin:$PATH
EOF

source /etc/profile.d/apache.sh

print_shell "apache 설치 완료"
httpd -v >&3

# 전용 시스템 계정 및 그룹 생성, 권한 부여
groupadd -r apache
useradd -r -g apache -s /sbin/nologin -d /usr/local/apache2 -c "Apache HTTP Server" apache
chown -R apache:apache /usr/local/apache2/logs

# httpd.conf 파일 수정
mkdir -p /usr/local/apache2/conf/sample
cp /usr/local/apache2/conf/httpd.conf /usr/local/apache2/conf/sample/httpd.conf.bak

sed -i \
    -E "s|^ServerRoot .*|ServerRoot /usr/local/apache2|" \
    -E "s|^PidFile .*|PidFile /usr/local/apache2/logs/httpd.pid|" \
    -E "s|^Listen .*|Listen 80|" \
    -E "s|^User .*|User apache|" \
    -E "s|^Group .*|Group apache|" \
    -E "s|^ServerAdmin .*|ServerAdmin [EMAIL_ADDRESS]|" \

    "/usr/local/apache2/conf/httpd.conf"
