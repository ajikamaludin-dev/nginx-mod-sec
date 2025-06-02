# Dockerfile for Nginx with Debian, HTTP/3 (QUIC), and ModSecurity
FROM debian:bookworm as builder

ARG NGINX_VERSION="1.28.0"
ARG OPENSSL_VERSION="3.5.0"

# Arguments untuk versi dan build options
ARG BUILD_DEPS=" \
    build-essential \
    libpcre2-dev \
    zlib1g-dev \
    libssl-dev \
    openssl \
    wget \
    git \
    cmake \
    ninja-build \
    pkg-config \
    libtool \
    automake \
    bison \
    flex \
    libxml2-dev \
    libcurl4-openssl-dev \
    libyajl-dev \
    liblmdb-dev \
    libgeoip-dev \
    libgd-dev \
    libmaxminddb-dev \
    libbz2-dev \
    libxslt1-dev \
    libperl-dev \
    ca-certificates \
    golang"

# Install dependencies
RUN apt-get update
RUN apt-get install -y --no-install-recommends $BUILD_DEPS
RUN rm -rf /var/lib/apt/lists/*

# Download dan extract Nginx source
WORKDIR /usr/src
RUN wget --no-check-certificate -q "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz"
RUN tar -xzf nginx-${NGINX_VERSION}.tar.gz
RUN rm nginx-${NGINX_VERSION}.tar.gz

RUN wget --no-check-certificate -q "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
RUN tar -xzf openssl-${OPENSSL_VERSION}.tar.gz

# Build boringssl (required for QUIC)
WORKDIR /usr/src
RUN git config --global http.sslVerify false
RUN git config --global advice.detachedHead false

RUN git clone --recursive https://github.com/cloudflare/quiche

# RUN mkdir -p /usr/local/boringssl/lib
# RUN git clone --depth 1 https://github.com/google/boringssl.git
# RUN cd boringssl && \
#     mkdir build && \
#     cd build && \
#     cmake -GNinja .. && \
#     ninja && \
#     ls && \
#     cp libcrypto.a /usr/local/boringssl/lib && \
#     cp libssl.a /usr/local/boringssl/lib
# RUN cp -r boringssl/include /usr/local/boringssl

# Build ModSecurity v3
WORKDIR /usr/src
RUN git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity && \
    cd ModSecurity && \
    git submodule init && \
    git submodule update && \
    ./build.sh && \
    ./configure && \
    make -j 6 && \
    make install

# Build ModSecurity-nginx connector
WORKDIR /usr/src
RUN git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git

# Build Nginx with all modules
WORKDIR /usr/src/nginx-${NGINX_VERSION}
RUN ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/run/nginx.pid \
    --lock-path=/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --with-perl_modules_path=/usr/lib/perl5/vendor_perl \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_realip_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-openssl=/usr/src/openssl-${OPENSSL_VERSION} \
    --with-openssl-opt=enable-tls1_3 \
    --add-module=/usr/src/ModSecurity-nginx \
    --with-cc-opt='-Os -fstack-clash-protection -Wformat -Werror=format-security -fno-plt -g -I/usr/src/quiche/deps/boringssl/include' \
    --with-ld-opt='-Wl,--as-needed,-O1,--sort-common -Wl,-z,pack-relative-relocs -L/usr/src/quiche/target/release -Wl,--rpath=/usr/src/quiche/target/release' && \
    make -j 6 && \
    make install

# Download OWASP Core Rule Set
WORKDIR /etc/nginx
RUN git clone --depth 1 -b v3.3/master https://github.com/coreruleset/coreruleset /etc/nginx/owasp-modsecurity-crs && \
    mv /etc/nginx/owasp-modsecurity-crs/crs-setup.conf.example /etc/nginx/owasp-modsecurity-crs/crs-setup.conf && \
    mv /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example \
    /etc/nginx/owasp-modsecurity-crs/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf && \
    mv /etc/nginx/owasp-modsecurity-crs/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example \
    /etc/nginx/owasp-modsecurity-crs/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf

# Create runtime directories
RUN mkdir -p /var/cache/nginx /var/log/nginx /run/nginx && \
    useradd -r -s /usr/sbin/nologin nginx

# Create modsecurity config
RUN mkdir -p /etc/nginx/modsec && \
    cp /usr/src/ModSecurity/modsecurity.conf-recommended /etc/nginx/modsec/modsecurity.conf && \
    cp /usr/src/ModSecurity/unicode.mapping /etc/nginx/modsec/

# Create final image
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update
RUN apt-get install -y --no-install-recommends \
    libpcre3 \
    zlib1g \
    libssl3 \
    libxml2 \
    libcurl4 \
    libyajl2 \
    liblmdb0 \
    libgeoip1 \
    libgd3 \
    libmaxminddb0 \
    libbz2-1.0 \
    libxslt1.1 \
    libperl5.36 \
    ca-certificates \
    curl
RUN rm -rf /var/lib/apt/lists/*

# Copy from builder
COPY --from=builder /usr/local/modsecurity/lib/libmodsecurity.so.3 /usr/lib/x86_64-linux-gnu/
COPY --from=builder /usr/src/ModSecurity-nginx /usr/src/ModSecurity-nginx
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /var/cache/nginx /var/cache/nginx
COPY --from=builder /var/log/nginx /var/log/nginx
COPY --from=builder /run/nginx /run/nginx
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group

# Configure ModSecurity
RUN sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/nginx/modsec/modsecurity.conf && \
    echo "Include /etc/nginx/owasp-modsecurity-crs/crs-setup.conf" >> /etc/nginx/modsec/modsecurity.conf && \
    echo "Include /etc/nginx/owasp-modsecurity-crs/rules/*.conf" >> /etc/nginx/modsec/modsecurity.conf

# Create sample vhost with ModSecurity protection
RUN mkdir -p /etc/nginx/conf.d
COPY default.conf  /etc/nginx/conf.d/default.conf

# Create default content
RUN mkdir -p /var/www/html 
COPY index.html /var/www/html/index.html

# Expose ports
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]