# -------------- Build-time variables --------------
ARG PHP_VERSION="8.0"
ARG ALPINE_VERSION="3.16"
# ---------------------------------------------------
### Build PHP base
FROM php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION}

COPY --chown=9000:9000 rootfs /

# BUILD: define build variables
ARG ADMINER_REPO="https://github.com/vrana/adminer"
ARG	ADMINER_VERSION="4.8.1"
ARG	ADMINER_DOWNLOAD_SHA256="2fd7e6d8f987b243ab1839249551f62adce19704c47d3d0c8dd9e57ea5b9c6b3"
ARG	ADMINER_COMMIT="1f173e18bdf0be29182e0d67989df56eadea4754"
ARG USER="adminer"
ARG UID="9000"
ARG GID="9000"

# RUNTIME: define environment variables
ENV ADMINER_HOME="/adminer"

WORKDIR /tmp/builder

RUN	echo "upload_max_filesize = 128M" >> /usr/local/etc/php/conf.d/0-upload_large_dumps.ini \
    &&	echo "post_max_size = 128M" >> /usr/local/etc/php/conf.d/0-upload_large_dumps.ini \
    &&	echo "memory_limit = 1G" >> /usr/local/etc/php/conf.d/0-upload_large_dumps.ini \
    &&	echo "max_execution_time = 600" >> /usr/local/etc/php/conf.d/0-upload_large_dumps.ini \
    &&	echo "max_input_vars = 5000" >> /usr/local/etc/php/conf.d/0-upload_large_dumps.ini

RUN set -x && apk -U upgrade --available --no-cache \
# BUILD: add build dependencies
    && apk add -t build-deps --no-cache \
        $PHPIZE_DEPS \
        curl \
        git \
    && curl -sSLf \
        -o /usr/local/bin/install-php-extensions \
        https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions \
    && chmod +x /usr/local/bin/install-php-extensions \
    && install-php-extensions \
        mysqli \
        pdo_mysql \
        pdo_pgsql \
# BUILD: download and install adminer
    && curl -fsSL "${ADMINER_REPO}/releases/download/v$ADMINER_VERSION/adminer-$ADMINER_VERSION.php" -o adminer.php \
    && echo "$ADMINER_DOWNLOAD_SHA256  adminer.php" |sha256sum -c - \
    && git clone --recurse-submodules=designs --depth 1 --shallow-submodules --branch "v$ADMINER_VERSION" ${ADMINER_REPO}.git /tmp/git \
    && commit="$(git -C /tmp/git/ rev-parse HEAD)" \
    && [ "$commit" = "$ADMINER_COMMIT" ] \
    && cp -r /tmp/git/designs/ /tmp/git/plugins/ . \
    && ln -s /usr/local/bin/php /usr/bin/php \
    && chmod +x /usr/local/bin/* \
# RUNTIME: add runtime group and user
    && addgroup ${USER} -g ${GID} \
    && adduser -s /sbin/nologin -G ${USER} -u ${UID} -D -h ${ADMINER_HOME} --gecos "" ${USER} \
    && chown -R ${UID}:${GID} ${ADMINER_HOME} /tmp/* \
# CLEANUP: Remove source files, build dependencies, etc.
    && apk del build-deps \
    && rm -rf /var/cache/apk/* /usr/local/bin/install-php-extensions /tmp/git

WORKDIR ${ADMINER_HOME}
ENTRYPOINT	[ "entrypoint.sh", "docker-php-entrypoint" ]
USER ${USER}
CMD	[ "php-fpm" ]

