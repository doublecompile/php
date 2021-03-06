#!/usr/bin/env bash

set -e

if [[ -n "${DEBUG}" ]]; then
    set -x
fi

SSH_DIR=/home/www-data/.ssh

exec_tpl() {
    gotpl "/etc/gotpl/$1" > "$2"
}

exec_init_scripts() {
    shopt -s nullglob
    for f in /docker-entrypoint-init.d/*.sh; do
        echo "$0: running $f"
        . "$f"
    done
    shopt -u nullglob
}

fix_permissions() {
    sudo fix-permissions.sh www-data www-data "${APP_ROOT}"

    if [[ -n "${PHP_XDEBUG_TRACE_OUTPUT_DIR}" ]]; then
        mkdir -p "${PHP_XDEBUG_TRACE_OUTPUT_DIR}"
    fi

    if [[ -n "${PHP_XDEBUG_PROFILER_OUTPUT_DIR}" ]]; then
        mkdir -p "${PHP_XDEBUG_PROFILER_OUTPUT_DIR}"
    fi
}

init_keys() {
    if [[ -n "${SSH_PRIVATE_KEY}" ]]; then
        exec_tpl "id_rsa.tpl" "${SSH_DIR}/id_rsa"
        chmod -f 600 "${SSH_DIR}/id_rsa"
        unset SSH_PRIVATE_KEY
    fi
}

init_sshd() {
    if [[ -n "${SSH_PUBLIC_KEYS}" ]]; then
        exec_tpl "authorized_keys.tpl" "${SSH_DIR}/authorized_keys"
        unset SSH_PUBLIC_KEYS
    fi

    sshd-init-env.sh
    sudo sshd-generate-keys.sh
}

process_templates() {
    exec_tpl "docker-php.ini.tpl" "${PHP_INI_DIR}/conf.d/docker-php.ini"
    exec_tpl "docker-php-ext-apcu.ini.tpl" "${PHP_INI_DIR}/conf.d/docker-php-ext-apcu.ini"
    exec_tpl "docker-php-ext-geoip.ini.tpl" "${PHP_INI_DIR}/conf.d/docker-php-ext-geoip.ini"
    exec_tpl "docker-php-ext-opcache.ini.tpl" "${PHP_INI_DIR}/conf.d/docker-php-ext-opcache.ini"
    exec_tpl "docker-php-ext-xdebug.ini.tpl" "${PHP_INI_DIR}/conf.d/docker-php-ext-xdebug.ini"
    exec_tpl "zz-www.conf.tpl" "/usr/local/etc/php-fpm.d/zz-www.conf"

    if [[ "${PHP_DEBUG}" == 0 ]]; then
        exec_tpl "docker-php-ext-blackfire.ini.tpl" "${PHP_INI_DIR}/conf.d/docker-php-ext-blackfire.ini"
    fi

    sed -i '/^$/d' "${PHP_INI_DIR}/conf.d/docker-php-ext-xdebug.ini"
}

fix_permissions
init_keys
process_templates
exec_init_scripts

if [[ $1 == "make" ]]; then
    exec "${@}" -f /usr/local/bin/actions.mk
else
    if [[ "${1} ${2}" == "sudo /usr/sbin/sshd" ]]; then
        init_sshd
    elif [[ "${1} ${2}" == "sudo crond" ]]; then
        exec_tpl "crontab.tpl" "/etc/crontabs/www-data"
    fi

    exec /usr/local/bin/docker-php-entrypoint "${@}"
fi
