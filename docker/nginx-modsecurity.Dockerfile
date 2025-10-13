# #######################################
# Docs:
# https://www.linode.com/docs/guides/securing-nginx-with-modsecurity/
# https://github.com/owasp-modsecurity/ModSecurity/wiki/Compilation-recipes-for-v3.x#ubuntu-2210
# #######################################

# FROM nginx:stable AS base
# nginx version 1.29.2
# https://hub.docker.com/layers/library/nginx/1.29.2/images
FROM nginx@sha256:ac03974aaaeb5e3fbe2ab74d7f2badf1388596f6877cbacf78af3617addbba9a AS base
WORKDIR /etc/nginx/

FROM base AS compilemodsecurity

# Install utilities
RUN apt update && \
    apt install -y git wget

# Clone modsecurity
WORKDIR /opt/ModSecurity/
RUN git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity .

# Clone modsecurity-nginx connector
WORKDIR /opt/ModSecurity-nginx/
RUN git clone --depth 1 --single-branch https://github.com/SpiderLabs/ModSecurity-nginx .

# Dowload nginx source (will be used to recompile nginx with dynamic module)
WORKDIR /opt/
RUN wget "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" -O nginx.tar.gz && \
    tar -xvzmf nginx.tar.gz && \
    rm nginx.tar.gz

# Install compile-time dependencies
RUN apt install -y \
    g++ \
    apt-utils \
    autoconf \
    automake \
    build-essential \
    libcurl4-openssl-dev \
    libgeoip-dev \
    liblmdb-dev \
    libpcre2-dev \
    libtool \
    libxml2-dev \
    libyajl-dev \
    pkgconf \
    zlib1g-dev

# Compile modsecurity
WORKDIR /opt/ModSecurity/
RUN git submodule init && \
    git submodule update && \
    ./build.sh && \
    ./configure --with-pcre2 && \
    make && \
    make install

# Compile nginx with modsecurity-nginx connector
WORKDIR /etc/nginx/
RUN ORIGINAL_CONFIG=$(nginx -V 2>&1 | sed -n -e 's/^.*arguments: //p')
RUN cd /opt/"nginx-${NGINX_VERSION}" && \
    ./configure --add-dynamic-module=../ModSecurity-nginx --with-compat $ORIGINAL_CONFIG && \
    make modules && \
    cp objs/ngx_http_modsecurity_module.so /etc/nginx/modules

FROM base AS release

# Install runtime dependencies
RUN apt update && \
    apt install -y \
        libyajl2

# Copy modsecurity module
COPY --from=compilemodsecurity /usr/local/modsecurity /usr/local/modsecurity
COPY --from=compilemodsecurity /etc/nginx/modules/ngx_http_modsecurity_module.so /etc/nginx/modules

WORKDIR /etc/nginx/
EXPOSE 80 443
ENTRYPOINT ["nginx", "-g", "daemon off;"]
