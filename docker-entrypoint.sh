#!/bin/bash


# wait for a given host:port to become available
#
# $1 host
# $2 port
function dockerwait {
    while ! exec 6<>/dev/tcp/"$1"/"$2"; do
        warn "$(date) - waiting to connect $1 $2"
        sleep 5
    done
    success "$(date) - connected to $1 $2"

    exec 6>&-
    exec 6<&-
}


function info () {
    printf "\r  [\033[00;34mINFO\033[0m] %s\n" "$1"
}


function warn () {
    printf "\r  [\033[00;33mWARN\033[0m] %s\n" "$1"
}


function success () {
    printf "\r\033[2K  [\033[00;32m OK \033[0m] %s\n" "$1"
}


function fail () {
    printf "\r\033[2K  [\033[0;31mFAIL\033[0m] %s\n" "$1"
    echo ''
    exit 1
}


# wait for services to become available
# this prevents race conditions using fig
function wait_for_services {
    if [[ "$WAIT_FOR_DB" ]] ; then
        dockerwait "$DBSERVER" "$DBPORT"
    fi
    if [[ "$WAIT_FOR_CACHE" ]] ; then
        dockerwait "$CACHESERVER" "$CACHEPORT"
    fi
    if [[ "$WAIT_FOR_RUNSERVER" ]] ; then
        dockerwait "$RUNSERVER" "$RUNSERVERPORT"
    fi
    if [[ "$WAIT_FOR_HOST_PORT" ]]; then
        dockerwait "$DOCKER_ROUTE" "$WAIT_FOR_HOST_PORT"
    fi
}


function defaults {
    : "${DBTYPE:=sqlite3}"
    : "${DBSERVER:=db}"
    : "${DBPORT:=5432}"
    : "${DBUSER:=webapp}"
    : "${DBNAME:=${DBUSER}}"
    : "${DBPASS:=${DBUSER}}"

    : "${EXPLORER_DBTYPE:=sqlite3}"
    : "${DEXPLORER_BSERVER:=db}"
    : "${DEXPLORER_BPORT:=5432}"
    : "${DEXPLORER_BUSER:=webapp}"
    : "${DEXPLORER_BNAME:=${DBUSER}}"
    : "${DEXPLORER_BPASS:=${DBUSER}}"

    : "${DOCKER_ROUTE:=$(/sbin/ip route|awk '/default/ { print $3 }')}"

    : "${UWSGI_OPTS:=/app/uwsgi/docker.ini}"
    : "${RUNSERVER:=runserver}"
    : "${RUNSERVERPORT:=8000}"
    : "${RUNSERVER_CMD:=runserver}"
    : "${CACHESERVER:=cache}"
    : "${CACHEPORT:=11211}"
    : "${MEMCACHE:=${CACHESERVER}:${CACHEPORT}}"

    export DBTYPE DBSERVER DBPORT DBUSER DBNAME DBPASS MEMCACHE DOCKER_ROUTE
    export EXPLORER_DBTYPE DEXPLORER_BSERVER DEXPLORER_BPORT DEXPLORER_BUSER DEXPLORER_BNAME DEXPLORER_BPASS
    export UWSGI_OPTS
}


function _django_check_deploy {
    info "running check --deploy"
    set -x
    django-admin.py check --deploy --settings="${DJANGO_SETTINGS_MODULE}" 2>&1 | tee "${LOG_DIRECTORY}"/uwsgi-check.log
    set +x
}


function _django_migrate {
    info "running migrate"
    set -x
    django-admin.py migrate --noinput --settings="${DJANGO_SETTINGS_MODULE}" 2>&1 | tee "${LOG_DIRECTORY}"/uwsgi-migrate.log
    set +x
}


function _django_collectstatic {
    info "running collectstatic"
    set -x
    django-admin.py collectstatic --noinput --settings="${DJANGO_SETTINGS_MODULE}" 2>&1 | tee "${LOG_DIRECTORY}"/uwsgi-collectstatic.log
    set +x
}


function _runserver() {
    : "${RUNSERVER_OPTS=${RUNSERVER_CMD} 0.0.0.0:${RUNSERVERPORT} --settings=${DJANGO_SETTINGS_MODULE}}"

    _django_collectstatic
    _django_migrate

    info "RUNSERVER_OPTS is ${RUNSERVER_OPTS}"
    set -x
    # shellcheck disable=SC2086
    exec django-admin.py ${RUNSERVER_OPTS}
}


trap exit SIGHUP SIGINT SIGTERM
defaults
env | grep -iv PASS | sort
wait_for_services
mkdir -p "${LOG_DIRECTORY}" || true

# prod uwsgi entrypoint
if [ "$1" = 'uwsgi' ]; then
    info "[Run] Starting prod uwsgi"

    _django_collectstatic
    _django_migrate
    _django_check_deploy

    set -x
    exec uwsgi --die-on-term --ini "${UWSGI_OPTS}"
fi

# runserver entrypoint
if [ "$1" = 'runserver' ]; then
    info "[Run] Starting runserver"
    _runserver
fi

# runserver_plus entrypoint
if [ "$1" = 'runserver_plus' ]; then
    info "[Run] Starting runserver_plus"
    RUNSERVER_CMD=runserver_plus
    _runserver
fi

warn "[RUN]: Builtin command not provided [runserver|runserver_plus|uwsgi]"
info "[RUN]: $*"

set -x
# shellcheck disable=SC2086 disable=SC2048
exec "$@"
