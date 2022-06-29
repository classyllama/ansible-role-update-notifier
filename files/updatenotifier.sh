#!/usr/bin/env bash

set -ue

DBFILE='updatenotifier.db'
SQ='/usr/bin/sqlite3'
CONFIG_FILE='updatenotifier.json'

if [ ! -f "${SQ}" ]; then
    echo "SQLite3 isn't installed. Please install it first."
    exit -1;
fi

if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Configuration file isn't exist. Please create it first."
    exit -1;
fi

if [ ! -f "${DBFILE}" ]; then
    echo "${DBFILE} isn't exist, creating a new one.."
    ${SQ} ${DBFILE} 'CREATE TABLE UPGRADES(ID INTEGER PRIMARY KEY AUTOINCREMENT, TIMESTAMP DATETIME DEFAULT CURRENT_TIMESTAMP, PACKAGENAME TEXT, RUNNING_VERSION TEXT, INSTALLED_VERSION TEXT, IS_NOTIFIED INT);'
fi

# Read config
for EACH_ENTRY in $(cat ${CONFIG_FILE} | jq -r '.[] | @base64'); do

  CLIENT_NAME=$(printf "%s\n" ${EACH_ENTRY} | base64 --decode | jq -r '.CLIENT_NAME')
  EMAILS=$(printf "%s\n" ${EACH_ENTRY} | base64 --decode | jq -r '.EMAILS')
  REDIS_HOST=$(printf "%s\n" ${EACH_ENTRY} | base64 --decode | jq -r '.REDIS_HOST')
  REDIS_PORT=$(printf "%s\n" ${EACH_ENTRY} | base64 --decode | jq -r '.REDIS_PORT')
  ES_USER=$(printf "%s\n" ${EACH_ENTRY} | base64 --decode | jq -r '.ES_USER')
  ES_PASS=$(printf "%s\n" ${EACH_ENTRY} | base64 --decode | jq -r '.ES_PASS')
  ES_HOST=$(printf "%s\n" ${EACH_ENTRY} | base64 --decode | jq -r '.ES_HOST')
  ES_PORT=$(printf "%s\n" ${EACH_ENTRY} | base64 --decode | jq -r '.ES_PORT')
  CHECK_REDIS=$(printf "%s\n" ${EACH_ENTRY} | base64 --decode | jq -r '.CHECK_REDIS')
  CHECK_ELASTIC=$(printf "%s\n" ${EACH_ENTRY} | base64 --decode | jq -r '.CHECK_ELASTIC')
  CHECK_MYSQL=$(printf "%s\n" ${EACH_ENTRY} | base64 --decode | jq -r '.CHECK_MYSQL')

done

# Check versions
# MYSQL
if [ ${CHECK_MYSQL} == "1" ]; then
  MYSQL_RUNNING_VERSION=$(mysql -e 'show global variables like "version"' -sN |awk {' print $2 '} |awk -F "-" {' print $1 '})
  MYSQL_INSTALLED_VERSION=$(rpm -qa |grep -i percona-server-server |awk -F "-" {' print $5 '})
  echo "`date +"%D %T"` Running MySQL version: ${MYSQL_RUNNING_VERSION}"
  echo "`date +"%D %T"` Installed MySQL version: ${MYSQL_INSTALLED_VERSION}"

  # Add to database
  if [ ${MYSQL_RUNNING_VERSION} != ${MYSQL_INSTALLED_VERSION} ]; then

    MYSQL_IS_KNOWN_UPGRADE=$(${SQ} ${DBFILE} "SELECT * FROM UPGRADES WHERE PACKAGENAME = \"Mysql\" AND RUNNING_VERSION = ${MYSQL_RUNNING_VERSION} AND INSTALLED_VERSION = ${MYSQL_INSTALLED_VERSION}" |wc -l)
    if [ ${MYSQL_IS_KNOWN_UPGRADE} == '0' ]; then
      ${SQ} ${DBFILE} "INSERT INTO UPGRADES (PACKAGENAME, RUNNING_VERSION, INSTALLED_VERSION, IS_NOTIFIED) VALUES (\"Mysql\", \"${MYSQL_RUNNING_VERSION}\", \"${MYSQL_INSTALLED_VERSION}\", \"0'\";"
    fi

  fi
fi

# Redis
if [ ${CHECK_REDIS} == "1" ]; then
  REDIS_RUNNING_VERSION=$(redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} info |grep redis_version |awk -F ":" {' print $2 '} |tr -d '\r')
  REDIS_INSTALLED_VERSION=$(rpm -qa |grep -i redis |grep -v pecl |awk -F "-" {' print $2 '})
  echo "`date +"%D %T"` Running Redis version: ${REDIS_RUNNING_VERSION}"
  echo "`date +"%D %T"` Installed Redis version: ${REDIS_INSTALLED_VERSION}"

  # Add to database
  if [ ${REDIS_RUNNING_VERSION} != ${REDIS_INSTALLED_VERSION} ]; then

    REDIS_IS_KNOWN_UPGRADE=$(${SQ} ${DBFILE} "SELECT * FROM UPGRADES WHERE PACKAGENAME = \"Redis\" AND RUNNING_VERSION = \"${REDIS_RUNNING_VERSION}\" AND INSTALLED_VERSION = \"${REDIS_INSTALLED_VERSION}\"" |wc -l)
    if [ ${REDIS_IS_KNOWN_UPGRADE} == "0" ]; then
      ${SQ} ${DBFILE} "INSERT INTO UPGRADES (PACKAGENAME, RUNNING_VERSION, INSTALLED_VERSION, IS_NOTIFIED) VALUES (\"Redis\", \"${REDIS_RUNNING_VERSION}\", \"${REDIS_INSTALLED_VERSION}\", \"0\");"
    fi

  fi
fi

# ElasticSearch
if [ ${CHECK_ELASTIC} == "1" ]; then
  ELASTIC_RUNNING_VERSION=`curl -su ${ES_USER}:${ES_PASS} ${ES_HOST}:${ES_PORT} | jq -r '.version.number'`
  ELASTIC_INSTALLED_VERSION=`rpm -qa |grep -i elasticsearch |awk -F "-" {' print $2 '}`
  echo "`date +"%D %T"` Running ElasticSearch version: ${ELASTIC_RUNNING_VERSION}"
  echo "`date +"%D %T"` Installed ElasticSearch version: ${ELASTIC_INSTALLED_VERSION}"

  # Add to database
  if [ ${ELASTIC_RUNNING_VERSION} != ${ELASTIC_INSTALLED_VERSION} ]; then

    ELASTIC_IS_KNOWN_UPGRADE=$(${SQ} ${DBFILE} "SELECT * FROM UPGRADES WHERE PACKAGENAME = \"Elasticsearch\" AND RUNNING_VERSION = \"${ELASTIC_RUNNING_VERSION}\" AND INSTALLED_VERSION = \"${ELASTIC_INSTALLED_VERSION}\"" |wc -l)
    if [ ${ELASTIC_IS_KNOWN_UPGRADE} == "0" ]; then
      ${SQ} ${DBFILE} "INSERT INTO UPGRADES (PACKAGENAME, RUNNING_VERSION, INSTALLED_VERSION, IS_NOTIFIED) VALUES (\"Elasticsearch\", \"${ELASTIC_RUNNING_VERSION}\", \"${ELASTIC_INSTALLED_VERSION}\", \"0\");"
    fi

  fi
fi

# Send notifications
MYSQL_NEEDS_NOTIFY=$(${SQ} ${DBFILE} "SELECT * FROM UPGRADES WHERE PACKAGENAME = \"Mysql\" AND RUNNING_VERSION = \"${MYSQL_RUNNING_VERSION}\" AND INSTALLED_VERSION = \"${MYSQL_INSTALLED_VERSION}\" AND IS_NOTIFIED = \"0\"" |wc -l)
if [ ${MYSQL_NEEDS_NOTIFY} == "1" ]; then
    # Notify via email
    echo "MySQL for ${CLIENT_NAME} on host `hostname` needs to be restarted, running version: ${MYSQL_RUNNING_VERSION}, installed version: ${MYSQL_INSTALLED_VERSION}" |mail -s "Update notification from ${CLIENT_NAME} on host `hostname`" ${EMAILS}
    ${SQ} ${DBFILE} "UPDATE UPGRADES SET IS_NOTIFIED = \"1\" WHERE PACKAGENAME = \"Mysql\" AND RUNNING_VERSION = \"${MYSQL_RUNNING_VERSION}\" AND INSTALLED_VERSION = \"${MYSQL_INSTALLED_VERSION}\""
    echo "`date +"%D %T"` MySQL for ${CLIENT_NAME} on host `hostname` needs to be restarted, running version: ${MYSQL_RUNNING_VERSION}, installed version: ${MYSQL_INSTALLED_VERSION}"
fi


REDIS_NEEDS_NOTIFY=$(${SQ} ${DBFILE} "SELECT * FROM UPGRADES WHERE PACKAGENAME = \"Redis\" AND RUNNING_VERSION = \"${REDIS_RUNNING_VERSION}\" AND INSTALLED_VERSION = \"${REDIS_INSTALLED_VERSION}\" AND IS_NOTIFIED = \"0\"" |wc -l)
if [ ${REDIS_NEEDS_NOTIFY} == "1" ]; then
    # Notify via email
    echo "Redis for ${CLIENT_NAME} on host `hostname` needs to be restarted, running version: ${REDIS_RUNNING_VERSION}, installed version: ${REDIS_INSTALLED_VERSION}" |mail -s "Update notification from ${CLIENT_NAME} on host `hostname`" ${EMAILS}
    ${SQ} ${DBFILE} "UPDATE UPGRADES SET IS_NOTIFIED = \"1\" WHERE PACKAGENAME = \"Redis\" AND RUNNING_VERSION = \"${REDIS_RUNNING_VERSION}\" AND INSTALLED_VERSION = \"${REDIS_INSTALLED_VERSION}\""
    echo "`date +"%D %T"` Redis for ${CLIENT_NAME} on host `hostname` needs to be restarted, running version: ${REDIS_RUNNING_VERSION}, installed version: ${REDIS_INSTALLED_VERSION}"
fi

ELASTIC_NEEDS_NOTIFY=$(${SQ} ${DBFILE} "SELECT * FROM UPGRADES WHERE PACKAGENAME = \"Elasticsearch\" AND RUNNING_VERSION = \"${ELASTIC_RUNNING_VERSION}\" AND INSTALLED_VERSION = \"${ELASTIC_INSTALLED_VERSION}\" AND IS_NOTIFIED = \"0\"" |wc -l)
if [ ${ELASTIC_NEEDS_NOTIFY} == "1" ]; then
    # Notify via email
    echo "Elasticsearch for ${CLIENT_NAME} on host `hostname` needs to be restarted, running version: ${ELASTIC_RUNNING_VERSION}, installed version: ${ELASTIC_INSTALLED_VERSION}" |mail -s "Update notification from ${CLIENT_NAME} on host `hostname`" ${EMAILS}
    ${SQ} ${DBFILE} "UPDATE UPGRADES SET IS_NOTIFIED = \"1\" WHERE PACKAGENAME = \"Elasticsearch\" AND RUNNING_VERSION = \"${ELASTIC_RUNNING_VERSION}\" AND INSTALLED_VERSION = \"${ELASTIC_INSTALLED_VERSION}\""
    echo "`date +"%D %T"` Elasticsearch for ${CLIENT_NAME} on host `hostname` needs to be restarted, running version: ${ELASTIC_RUNNING_VERSION}, installed version: ${ELASTIC_INSTALLED_VERSION}"
fi
