#!/usr/bin/env bash
# by klzsysy

set -ex

if [ "$#" -ne 0 ];then
    if which $1 > /dev/null ;then
        exec "$@"
        exit $?
    fi
fi

SYNC_INTERVAL=${SYNC_INTERVAL:='30'}

WEEK_SYNC_TIME=${WEEK_SYNC_TIME:='all'}
SERVER_URL=${SERVER_URL:-'http://localhost'}
SLEEP=$(( ${SYNC_INTERVAL} * 60 ))
# APP_COUNTRY_NAME=${APP_COUNTRY_NAME:-'China'}
# APP_COUNTRY_CODE=${APP_COUNTRY_CODE:-'cn'}
PROXY_URL_PREFIX=${PROXY_URL_PREFIX:-'zipcache'}
EXTERNAL_PORT=${EXTERNAL_PORT:-"80"}
HTTP_PORT=${HTTP_PORT:-'8080'}
OPTION=${OPTION:-'--no-progress'}


if [ "${WEEK_SYNC_TIME}" == 'all' ];then
    WEEK_SYNC_TIME=$(seq 1 7)
fi

if [ -n "${HTTP_PORT}" ];then
    sed -i "s/8080/${HTTP_PORT}/" /etc/nginx/conf.d/nginx-site.conf
fi

function info(){
    echo "$(date '+%F %T') - info: $@"
}

function handle_TERM()
{
        kill -s SIGTERM $(ps aux | grep -v grep| grep  'nginx: master' | awk '{print $2}')
        kill -s SIGTERM $(ps aux | grep -v grep| grep  'php-fpm: master' | awk '{print $2}')
        kill -s SIGTERM "${proxy_pid}"
        kill -s SIGTERM "${sleep_pid}"
        kill -s SIGTERM "${sync_pid}"
        wait "${sync_pid}"
        exit $?
}

function update_packages_json(){
    _SERVER_URL=$(echo "${SERVER_URL}" | sed 's#/#\\/#g')
    if [ "${EXTERNAL_PORT}" != "80" ];then
        _SERVER_URL="${_SERVER_URL}:${EXTERNAL_PORT}"
    fi
    _value="[{\"dist-url\":\"${_SERVER_URL}\/${PROXY_URL_PREFIX}\/%package%\/%reference%.%type%\",\"preferred\":true}]"
    gzip -cd public/packages.json.gz | jq ". += {\"mirrors\": ${_value}}" | gzip > public/_packages.json.gz
    mv -f public/_packages.json.gz public/packages.json.gz

    cd public && ln -sf packages.json.gz packages.json && cd -
}

function init_var(){
    sed -i "s#location /proxy#location /${PROXY_URL_PREFIX}#" nginx-site.conf
    cp -r nginx-site.conf /etc/nginx/conf.d/
    cp -f index.html public/index.html
}

init_var
trap 'handle_TERM' SIGTERM


nginx -t && nginx
python3 ./proxy.py &
proxy_pid=$!

composersync(){
    info "start sync ....."
    exec php bin/mirror create ${OPTION}  &
    sync_pid=$!
    wait ${sync_pid}
    update_packages_json
    info "sync end"

}


while true;
do
    if echo "${WEEK_SYNC_TIME}" | grep -q "$(date '+%u')" ;then
        composersync $@
        sleep $(( ${SYNC_INTERVAL} * 60 )) &
        sleep_pid=$!
        wait ${sleep_pid}
    else
        sleep 50 &
        sleep_pid=$!
        wait ${sleep_pid}
    fi
done
x
