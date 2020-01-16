#!/bin/bash

set -e

# expect oc to be in PATH by default
OC_TOOL="${OC_TOOL:-oc}"

# Override the image name when this is invoked from openshift ci                               
if [ -n "${OPENSHIFT_BUILD_NAMESPACE}" ]; then                                                   
        FULL_REGISTRY_IMAGE="registry.svc.ci.openshift.org/${OPENSHIFT_BUILD_NAMESPACE}/stable:performance-addon-operator-registry"
        echo "Openshift CI detected, deploying using image $FULL_REGISTRY_IMAGE"                   
fi   

${OC_TOOL} apply -f - <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    openshift.io/cluster-monitoring: "true"
  name: openshift-performance-addon
spec: {}
EOF

${OC_TOOL} apply -f - <<EOF
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-performance-addon-operatorgroup
  namespace: openshift-performance-addon
spec:
  targetNamespaces:
  - openshift-performance-addon
EOF
  
${OC_TOOL} apply -f - <<EOF
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: performance-addon-operator-catalogsource
  namespace: openshift-marketplace
spec:
  displayName: Openshift Performance Addon Operator
  icon:
    base64data: ""
    mediatype: ""
  image: ${FULL_REGISTRY_IMAGE}
  publisher: Red Hat
  sourceType: grpc
EOF

${OC_TOOL} apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: performance-addon-operator-subscription
  namespace: openshift-performance-addon
spec:
  channel: alpha
  name: performance-addon-operator
  source: performance-addon-operator-catalogsource
  sourceNamespace: openshift-marketplace
EOF

# Wait for performance-addon-operator deployment to be ready
until ${OC_TOOL} -n openshift-performance-addon get deploy/performance-operator; do
    echo "[INFO]: get performance-operator deployment"
    sleep 10
done
${OC_TOOL} -n openshift-performance-addon wait deploy/performance-operator --for condition=Available --timeout 5m

# Deploy performance-profile custom resource
${KUSTOMIZE} build cluster-setup/ci-cluster/performance/ | envsubst | ${OC_TOOL} apply -f -
