#!/usr/bin/env ksh
PATH=/usr/local/bin:${PATH}
IFS_DEFAULT="${IFS}"
#################################################################################

#################################################################################
#
#  Variable Definition
# ---------------------
#
APP_NAME=$(basename $0)
APP_DIR=$(dirname $0)
APP_VER="0.0.1"
APP_WEB="http://www.sergiotocalini.com.ar/"
TIMESTAMP=`date '+%s'`
CACHE_DIR=${APP_DIR}/tmp
CACHE_TTL=5                                      # IN MINUTES
#
#################################################################################

#################################################################################
#
#  Load Environment
# ------------------
#
[[ -f ${APP_DIR}/${APP_NAME%.*}.conf ]] && . ${APP_DIR}/${APP_NAME%.*}.conf

#
#################################################################################

#################################################################################
#
#  Function Definition
# ---------------------
#
usage() {
    echo "Usage: ${APP_NAME%.*} [Options]"
    echo ""
    echo "Options:"
    echo "  -a            Query arguments."
    echo "  -h            Displays this help message."
    echo "  -j            Jsonify output."
    echo "  -s ARG(str)   Section (default=stat)."
    echo "  -v            Show the script version."
    echo ""
    echo "Please send any bug reports to sergiotocalini@gmail.com"
    exit 1
}

version() {
    echo "${APP_NAME%.*} ${APP_VER}"
    exit 1
}

refresh_cache() {
    IFS=${IFS_DEFAULT}
    [[ -d ${CACHE_DIR} ]] || mkdir -p ${CACHE_DIR}
    file=${CACHE_DIR}/data.json
    if [[ $(( `stat -c '%Y' "${file}" 2>/dev/null`+60*${CACHE_TTL} )) -le ${TIMESTAMP} ]]; then
	header="Authorization: Token ${SEAFILE_TOKEN}"
	resource="${SEAFILE_URL}/api2/server-info/"
	server_info=`curl -s -H "${header}" "${resource}"|jq -c '.' 2>/dev/null`

	resource="${SEAFILE_URL}/api2/accounts/?scope=DB "
	resource+="${SEAFILE_URL}/api2/accounts/?scope=LDAP"
	for src in ${resource[@]}; do
	    for user in `curl -s -H "${header}" "${src}"|jq '.[]|"\(.email)|\(.source)"'`; do
		users+="${user} "
	    done
	done
	
	resource="${SEAFILE_URL}/api2/accounts"
	json_raw="{ \"server_info\": ${server_info}, \"accounts\":[], \"updated_on\": ${TIMESTAMP}}"
	for user in ${users[@]}; do
	    email=`echo ${user} | sed 's:"::g' | awk -F'|' '{print $1}'`
	    source=`echo ${user} | sed 's:"::g' | awk -F'|' '{print $2}'`
	    raw=`curl -s -H "${header}" "${resource}/${email}/"`
	    user_data=`echo "${raw}" | jq -c '.source="'${source}'"'`
	    json_raw=`echo "${json_raw}" | jq -c ".accounts+=[${user_data}]"`
	done
	echo "${json_raw}" | jq . 2>/dev/null > ${file}
    fi
    echo "${file}"
}

discovery() {
    resource=${1}
    json=$(refresh_cache)
    if [[ ${resource} == 'users' ]]; then
    	for u in `jq -r '.accounts[]|"\(.id)|\(.email)|\(.source)|\(.is_active)|\(.usage)"' ${json}`; do
    	    echo ${u}
    	done
    fi
    return 0
}

get_stats() {
    type=${1}
    resource=${2}
    name=${3}
    param1=${4}
    param2=${5}
    json=$(refresh_cache)
    if [[ ${type} =~ ^server$ ]]; then
	if [[ ${resource} == 'version' ]]; then
	    res=`jq -r ".server_info.version" ${json}`
	elif [[ ${resource} == 'storage_used_avg' ]]; then
	    raw=`jq -r ".accounts[]|(.usage * 100) / .total" ${json}`
	    all=`echo "${raw}" | wc -l | awk '{$1=$1};1'`
	    sum=`echo "${raw}" | awk '{n += $1}; END{printf("%.1f\n", n)}'`
	    res=`echo $(( ${sum:-0} / ${all} )) | awk '{printf("%.2f\n", $1)}'`
	elif [[ ${resource} == 'storage_used_median' ]]; then
	    raw=`jq -r ".accounts[]|(.usage * 100) / .total" ${json} | sort -n`
	    all=`echo "${raw}" | wc -l | awk '{$1=$1};1'`
	    [ $((${all}%2)) -ne 0 ] && let "all=all+1"
	    num=`echo $(( ${all} / 2))`
	    res=`sed -n "${num}"p <<< "${raw}"`
	elif [[ ${resource} == 'storage_used_mode' ]]; then
	    raw=`jq -r ".accounts[]|(.usage * 100) / .total" ${json} | sort -n`
	    res=`echo "${raw}" | uniq -c | sort -k 1 | tail -1 | awk '{print $2}'`
	fi
    elif [[ ${type} =~ ^user$ ]]; then
	if [[ ${resource} == 'storage_usage_perc' ]]; then
	    total=`jq -r ".accounts[]|select(.id==${name} and .source==\"${param1}\")|.total" ${json}`
	    usage=`jq -r ".accounts[]|select(.id==${name} and .source==\"${param1}\")|.usage" ${json}`
	    res=`echo $(( (${usage}*100)/${total} ))`
	elif [[ ${resource} == 'storage_usage' ]]; then
	    res=`jq -r ".accounts[]|select(.id==${name} and .source==\"${param1}\")|.usage" ${json}`
	elif [[ ${resource} == 'storage_total' ]]; then
	    res=`jq -r ".accounts[]|select(.id==${name} and .source==\"${param1}\")|.total" ${json}`
	fi
    fi
    echo ${res:-0}
}

get_service() {
    resource=${1}

    port=`echo "${SEAFILE_URL}" | sed -e 's|.*://||g' -e 's|/||g' | awk -F: '{print $2}'`
    pid=`sudo lsof -Pi :${port:-8080} -sTCP:LISTEN -t | head -1`
    rcode="${?}"
    if [[ ${resource} == 'listen' ]]; then
	if [[ ${rcode} == 0 ]]; then
	    res=1
	fi
    elif [[ ${resource} == 'uptime' ]]; then
	if [[ ${rcode} == 0 ]]; then
	    res=`sudo ps -p ${pid} -o etimes -h`
	fi
    fi
    echo ${res:-0}
    return 0
}

#
#################################################################################

#################################################################################
while getopts "s::a:s:uphvr:j:" OPTION; do
    case ${OPTION} in
	h)
	    usage
	    ;;
	s)
	    SECTION="${OPTARG}"
	    ;;
        j)
            JSON=1
            IFS=":" JSON_ATTR=(${OPTARG//p=})
            ;;
	a)
	    ARGS[${#ARGS[*]}]=${OPTARG//p=}
	    ;;
	r)
	    REPORT=1
	    REPORT_ATTR="${OPTARG}"
	    ;;
	v)
	    version
	    ;;
         \?)
            exit 1
            ;;
    esac
done

if [[ ${REPORT} -eq 1 ]]; then
    report_file=${CACHE_DIR}/zabbix.data
    items=( 'version' 'storage_used_avg' 'storage_used_median' 'storage_used_mode')
    echo -n "" > ${report_file}
    for item in ${items[@]}; do
	rval=$( get_stats 'server' ${item} )
	echo "\"`hostname -f`\" \"seabix[server, ${item}]\" ${TIMESTAMP} \"${rval}\"" >> ${report_file}
    done
    zabbix_sender -c ${REPORT_ATTR} -i ${report_file} -T
    exit 0
fi

if [[ ${JSON} -eq 1 ]]; then
    rval=$(discovery ${ARGS[*]})
    echo '{'
    echo '   "data":['
    count=1
    while read line; do
        IFS="|" values=(${line})
        output='{ '
        for val_index in ${!values[*]}; do
            output+='"'{#${JSON_ATTR[${val_index}]:-${val_index}}}'":"'${values[${val_index}]}'"'
            if (( ${val_index}+1 < ${#values[*]} )); then
                output="${output}, "
            fi
        done 
        output+=' }'
        if (( ${count} < `echo ${rval}|wc -l` )); then
            output="${output},"
        fi
        echo "      ${output}"
        let "count=count+1"
    done <<< ${rval}
    echo '   ]'
    echo '}'
else
    if [[ ${SECTION} == 'discovery' ]]; then
        rval=$(discovery ${ARGS[*]})
        rcode="${?}"
    elif [[ ${SECTION} == 'service' ]]; then
	rval=$( get_service ${ARGS[*]} )
	rcode="${?}"	
    else
	rval=$( get_stats ${SECTION} ${ARGS[*]} )
	rcode="${?}"
    fi
    echo ${rval:-0} | sed "s/null/0/g"
fi

exit ${rcode}
