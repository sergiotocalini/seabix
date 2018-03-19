#!/usr/bin/env ksh
SOURCE_DIR=$(dirname $0)
ZABBIX_DIR=/etc/zabbix
ZABBIX_CONF=/etc/zabbix/zabbix_agentd.conf

SEAFILE_URL=${1:-http://localhost:8000}
SEAFILE_TOKEN=${2}

mkdir -p ${ZABBIX_DIR}/scripts/agentd/seabix
cp -rv ${SOURCE_DIR}/seabix/seabix.conf.example    ${ZABBIX_DIR}/scripts/agentd/seabix/seabix.conf
cp -rv ${SOURCE_DIR}/seabix/seabix.sh              ${ZABBIX_DIR}/scripts/agentd/seabix/
cp -rv ${SOURCE_DIR}/seabix/zabbix_agentd.conf     ${ZABBIX_DIR}/zabbix_agentd.d/seabix.conf
sed -i "s|SEAFILE_URL=.*|SEAFILE_URL=\"${SEAFILE_URL}\"|g" ${ZABBIX_DIR}/scripts/agentd/seabix/seabix.conf
sed -i "s|SEAFILE_TOKEN=.*|SEAFILE_TOKEN=\"${SEAFILE_TOKEN}\"|g" ${ZABBIX_DIR}/scripts/agentd/seabix/seabix.conf

crontab -u zabbix -l > /tmp/zabbix-crontab
CRONTAB_LINE="00 * * * * ${ZABBIX_DIR}/scripts/agentd/seabix/seabix.sh -r ${ZABBIX_CONF}"
if ! [[ `grep "${CRONTAB_LINE}" /tmp/zabbix-crontab` ]]; then
    if ! [[ `grep "seabix.sh" /tmp/zabbix-crontab` ]]; then
	echo "${CRONTAB_LINE}" >> /tmp/zabbix-crontab
	crontab -u zabbix /tmp/zabbix-crontab
    fi
fi
rm /tmp/zabbix-crontab
