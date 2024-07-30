#!/bin/bash
# © Copyright IBM Corporation 2022, 2024
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

line_separator () {
  echo "####################### $1 #######################"
}

NAMESPACE=${1:-"cp4i"}
API_CONNECT_CLUSTER_NAME=ademo
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
BLOCK_STORAGE=${2:-"ocs-storagecluster-ceph-rbd"}
INSTALL_CP4I=${3:-true}

if [ -z $NAMESPACE ]
then
    echo "Usage: setup-software.sh <namespace for deployment>"
    exit 1
fi

NN=$(echo $NAMESPACE | sed 's/.*-\(.*\)/\1/')
echo "append with $NN"

oc new-project $NAMESPACE 2> /dev/null
oc project $NAMESPACE

oc apply -f resources/ibmedu-tls-cert.yaml -n $NAMESPACE

if [ "$INSTALL_CP4I" = true ] ; then
  oc patch storageclass $BLOCK_STORAGE -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
fi
echo "./install-operators.sh $NAMESPACE" 


./install-operators.sh $NAMESPACE


if [ "$INSTALL_CP4I" = true ] ; then
  echo ""
  line_separator "START - INSTALLING PLATFORM NAVIGATOR"
  cat $SCRIPT_DIR/resources/platform-nav.yaml_template |
  sed "s#{{NAMESPACE}}#$NAMESPACE#g;" | sed "s#{{NN}}#$NN#g;" > $SCRIPT_DIR/resources/platform-nav.yaml

oc apply -f resources/platform-nav.yaml
  sleep 30

  END=$((SECONDS+3600))
  PLATFORM_NAV=FAILED

  while [ $SECONDS -lt $END ]; do
    PLATFORM_NAV_PHASE=$(oc get platformnavigator platform-navigator -o=jsonpath={'.status.conditions[].type'})
    if [[ $PLATFORM_NAV_PHASE == "Ready" ]]
    then
      echo "Platform Navigator available"
      PLATFORM_NAV=SUCCESS
      break
    else
      echo "Waiting for Platform Navigator to be available"
      sleep 60
    fi
  done

  if [[ $PLATFORM_NAV == "SUCCESS" ]]
  then
    echo "SUCCESS"
  else
    echo "ERROR: Platform Navigator failed to install after 60 minutes"
    exit 1
  fi
  line_separator "SUCCESS - INSTALLING PLATFORM NAVIGATOR"
fi

echo ""
line_separator "START - INSTALLING API CONNECT"

cat $SCRIPT_DIR/resources/apic-cluster.yaml_template |
  sed "s#{{NAMESPACE}}#$NAMESPACE#g;" | sed "s#{{NN}}#$NN#g;" > $SCRIPT_DIR/resources/apic-cluster.yaml

oc apply -f resources/apic-cluster.yaml
sleep 30

END=$((SECONDS+3600))
APIC_INSTALL=FAILED

while [ $SECONDS -lt $END ]; do
    API_PHASE=$(oc get apiconnectcluster $API_CONNECT_CLUSTER_NAME -o=jsonpath={'..phase'})
    if [[ $API_PHASE == "Ready" ]]
    then
      echo "API Connect available"
      APIC_INSTALL=SUCCESS
      break
    else
      echo "Waiting for API Connect to be available"
      sleep 60
    fi
done

if [[ $APIC_INSTALL == "SUCCESS" ]]
then
  echo "SUCCESS"
else
  echo "ERROR: API Connect failed to install after 60 minutes"
  exit 1
fi

./configure-apiconnect.sh -n $NAMESPACE -r $API_CONNECT_CLUSTER_NAME

PLATFORM_NAV_USERNAME=$(oc get secret integration-admin-initial-temporary-credentials -o=jsonpath={.data.username} | base64 -d)
PLATFORM_NAV_PASSWORD=$(oc get secret integration-admin-initial-temporary-credentials -o=jsonpath={.data.password} | base64 -d)

line_separator "SUCCESS - INSTALLING API CONNECT"
PLATFORM_NAVIGATOR_URL=$(oc get route platform-navigator-pn -o jsonpath={'.spec.host'})
echo "Platform Navigator URL: https://$PLATFORM_NAVIGATOR_URL"
echo "Username: $PLATFORM_NAV_USERNAME"
echo "Password: $PLATFORM_NAV_PASSWORD"
echo ""
