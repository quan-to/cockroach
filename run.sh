#!/bin/bash

get_join_string() {
        echo "Looking for lead container to join..."

        LEADER_CREATE_INDEX=${NODE_CREATE_INDEX}
        LEADER_NAME=${NODE_NAME}

        SIBLINGS=`curl -s 'http://rancher-metadata/2015-12-19/self/service/containers' | cut -d= -f1`
        for index in ${SIBLINGS}
        do
                SIBLING_CREATE_INDEX=`curl -s "http://rancher-metadata/2015-12-19/self/service/containers/${index}/create_index"`
                SIBLING_STATE=`curl -s "http://rancher-metadata/2015-12-19/self/service/containers/${index}/state"`

                echo "Sibling Create Index = ${SIBLING_CREATE_INDEX}."
                echo "Sibling State = ${SIBLING_STATE}."

                if [ \( "${SIBLING_STATE}" = "running" -o "${SIBLING_STATE}" = "starting" \) -a ${SIBLING_CREATE_INDEX} -lt ${LEADER_CREATE_INDEX} ]
                then
                        LEADER_CREATE_INDEX=${SIBLING_CREATE_INDEX}
                        LEADER_NAME=`curl -s "http://rancher-metadata/2015-12-19/self/service/containers/${index}/name"`

                        echo "New Leader Name = ${LEADER_NAME}."
                fi
        done

        echo "Final Leader Name = ${LEADER_NAME}."

        if [ "${LEADER_NAME}" = "${NODE_NAME}" ]
        then
                echo "I'm the lead container."
        else
                JOIN_STRING="--join=${LEADER_NAME}:26257"
                echo "I'm not the lead container, joining ${LEADER_NAME} in ${MAX_WAIT} seconds..."
                sleep ${MAX_WAIT}
        fi
}

#
# Get current container's "number" and name.
NODE_CREATE_INDEX=`curl -s 'http://rancher-metadata/2015-12-19/self/container/create_index'`
NODE_NAME=`curl -s 'http://rancher-metadata/2015-12-19/self/container/name'`
echo "Node Name = ${NODE_NAME}."

#
# Wait between 1 to 10 seconds in the hope that at least one container "wins" and becomes the leader when they all start at the same time.
MAX_WAIT=15

#
# On start up we need to know whether we can join already running nodes.
JOIN_STRING=""
STORE_PATH=${STORE_PATH:-"/cockroach/cockroach-data/${NODE_NAME}"}

if [ "${LEADER_NAME}" = "${NODE_NAME}" ]
then
    echo "I'm the lead container."
else
    WAIT_TIME=$(( ( RANDOM % ${MAX_WAIT} )  + 15 ))
    echo "Waiting for ${WAIT_TIME} seconds before attempting to start..."
    sleep ${WAIT_TIME}
    echo "...starting up."

    LEADER_IP=$(dig +short ${LEADER_NAME})

    JOIN_STRING="--join=${LEADER_IP}:26257"
fi

TAGS=""

labels=$(curl -s "http://rancher-metadata/2015-12-19/self/host/labels")

for label in $labels
do
  echo $label | grep tag_ > /dev/null
  if [ $? -eq 0 ]
  then
    tag=$(curl -s "http://rancher-metadata/2015-12-19/self/host/labels/$label")
    echo "Adding tag ${tag} labeled as ${label} to server tags"
    if [[ ${TAGS} == "" ]]; then
        TAGS="${label}=${tag}"
    else
        TAGS="${TAGS},${label}=${tag}"
    fi
  fi
done

if [[ ${TAGS} == "" ]]; then
    CMD=""
else
    CMD="--locality=${TAGS}"
fi

host=$(hostname)
ip=$(ip addr show dev eth0 | grep inet | grep eth0 | awk '{print$2}' | cut -d/ -f1)

#
# Start the node.
exec /cockroach/cockroach start --insecure --host=${ip} --store=${STORE_PATH} ${JOIN_STRING} ${CMD} $@

echo "Background cockroach process finished, shutting down node."