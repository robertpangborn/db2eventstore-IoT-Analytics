#!/bin/bash

function usage()
{
cat <<-USAGE #| fmt
Pre-requisite:
- This script requires the SSL certificate to be the default self-signed certificate
- This currently only run on Event Store 2.0 installed with Watson Studio Local
- You have the public IP of the target Event Store 2.0 server
- You have the username and password of the Watson Studio Local on the Event Store server
========
Description:
This script will receive the argument of public IP of target Event Store 2.0 server,
user and password of the Watson Studio Local on the Event Store 2.0 server.
Then it will retrieve the clientkeystore file and it's password for the SSL connection
with Event Store 2.0. The /bluspark/external_conf/bluspark.conf file be created
with above information.

-----------
Usage: $0 [OPTIONS] [arg]
OPTIONS:
========
--IP  Public IP of target cluster.
--user User name of Watson Studio Local user
--password Password of Watson Studio Local user
USAGE
}

while [ -n "$1" ]; do
    case "$1" in
    -h|--help)
        usage >&2
        exit 0
        ;;
    --IP)
        IP="$2"
        shift 2
        ;;
    --user)
        EVENT_USER="$2"
        shift 2
        ;;
    --password)
        EVENT_PASSWORD="$2"
        shift 2
        ;;
    *)
        echo "Unknown option:$2"
        usage >&2
        exit 1
    esac
done

# IP, Evnet_User, Event_Password can be read from the environment variable set by `docker run -e`

if [ -z ${IP} ]; then
   echo "Error: Please pass in the public IP of your cluster using flag --IP" >&2
   usage >&2
   exit 1
fi

if [ -z ${EVENT_USER} ]; then
    echo "Error: Please pass in the Watson Studio Local user name using flag --user" >&2
    usage >&2
    exit 1
fi

if [ -z ${EVENT_PASSWORD} ]; then
    echo "Error: Please pass in the Watson Studio Local's password name using flag --password" >&2
    usage >&2
    exit 1
fi

# target path to store client ssl key
KEYDB_PATH="/var/lib/eventstore"
mkdir -p ${KEYDB_PATH}
# get bearerToken
bearerToken=`curl --silent -k -X GET https://${IP}/v1/preauth/validateAuth -u ${EVENT_USER}:${EVENT_PASSWORD} | python -c "import sys, json; print(json.load(sys.stdin)['accessToken'])"`
[ $? -ne 0 ] && echo "Not able to get bearerToken" && exit 2

# get clientkeystore file
curl --silent -k -X GET -H "authorization: Bearer $bearerToken" "https://${IP}:443/com/ibm/event/api/v1/oltp/keystore" -o ${KEYDB_PATH}/clientkeystore
[ $? -ne 0 ] && echo "Not able to get clientkeystore file" && exit 3

# get clientkeystore password
KEYDB_PASSWORD=$(curl --silent -k -i -X GET -H "authorization: Bearer $bearerToken" "https://${IP}:443/com/ibm/event/api/v1/oltp/keystore_password" | tail -1)
[ $? -ne 0 ] && echo "Not able to get clientkeystore password" && exit 4
# get server certificate
curl -k -X GET -H "authorization: Bearer $bearerToken" "https://${IP}:443/com/ibm/event/api/v1/oltp/certificate" -o ${KEYDB_PATH}/eventstore.pem
[ $? -ne 0 ] && echo "Not able to get server certificate" && exit 5

# export the KEYDB_PATH and KEYDB_PASSWORD only if it's in a container.
if [ -f "/.dockerenv" ]; then
    sed -i "/export KEYDB_PASSWORD=/d" ~/.bashrc
    sed -i "/export KEYDB_PATH=/d" ~/.bashrc
    sed -i "/export SERVER_CERT_PATH=/d" ~/.bashrc
    echo "export KEYDB_PASSWORD=${KEYDB_PASSWORD}" >> ~/.bashrc
    echo "export KEYDB_PATH=${KEYDB_PATH}/clientkeystore" >> ~/.bashrc
    echo "export SERVER_CERT_PATH=${KEYDB_PATH}/eventstore.pem" >> ~/.bashrc
    source ~/.bashrc
fi
