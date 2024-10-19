#!/bin/bash

# The prefix is split to /30 networks
# to form peer-2-peer connections.
PREFIX="10.8.0.0/16"
NUM_PEERS=200

SRV_A_IP="192.168.122.28"
SRV_A_PORT="30000"

SRV_B_IP="192.168.122.66"
SRV_B_PORT_START="10000"

SRV_A_OUTFILE="wg1.conf"
SRV_B_OUTFILE_PREFIX="wg"
SRV_B_OUTFILE_PREFIX="k8s-"

MTU=1420

# End configuration

SRV_A_WG_IP_ADDRESS="$(ipcalc-ng --no-decorate $PREFIX --minaddr)/$(ipcalc-ng --no-decorate $PREFIX --prefix)"

P2P_NETWORKS="$(ipcalc-ng -S 32 $PREFIX --no-decorate)"

__CURR_SRV_B_PORT="$SRV_B_PORT_START"

__SRV_A_PRIVKEY=$(wg genkey)
__SRV_A_PUBKEY=$(echo $__SRV_A_PRIVKEY | wg pubkey)

# Print headers.
cat <<EOF > $SRV_A_OUTFILE
[Interface]
Address = $SRV_A_WG_IP_ADDRESS
ListenPort = $SRV_A_PORT
PrivateKey = $__SRV_A_PRIVKEY
MTU = $MTU

EOF

__INDEX=-2
# Generate so many peers in one file
__SRV_B_SECRETS_FILE="$SRV_B_OUTFILE_PREFIX-secrets.yaml"
__SRV_B_STS_FILE="$SRV_B_OUTFILE_PREFIX-sts.yaml"

cat <<EOF > $__SRV_B_SECRETS_FILE
apiVersion: v1
# I do not care about security in this test.
kind: ConfigMap
metadata:
    name: wg-peers
data:

EOF

cat <<EOF > $__SRV_B_STS_FILE
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: wg-peers
spec:
  selector:
    matchLabels:
      kubernetes.io/application: wg-peers
  replicas: 1
  podManagementPolicy: Parallel
  template:
    metadata:
      labels:
        kubernetes.io/application: wg-peers
    spec:
      securityContext:
        runAsUser: 0
      volumes:
        - name: wg-peers-config
          configMap:
            name: wg-peers
      containers:
        - name: wireguard
          image: ghcr.io/ermakovdmitriy/wireguard-test-container:main
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          securityContext:
            runAsUser: 0
            privileged: true
          command:
            - bash
            - "-c"
            - |
              set -o pipefail
              PEER_NUMBER=\$(echo \$POD_NAME | rev | cut -d'-' -f1 | rev)
              echo "Starting Wireguard with PEER \$PEER_NUMBER"
              wg-quick up wg\$PEER_NUMBER
              sleep infinity
          volumeMounts:
            - name: wg-peers-config
              mountPath: "/etc/wireguard/"
EOF

for __NET in $P2P_NETWORKS; do
    if test $__INDEX -gt $NUM_PEERS; then
	echo "Generated $NUM_PEERS, stop"
	break
    fi

    
    if test $__INDEX -lt 0; then
	echo "Skipping the first network prefix ($__NET) as it will be used by SRV_A"
	__INDEX=$(($__INDEX+1))
        continue
    fi

    echo "Generating peer $__NET"

    __SRV_B_WG_IP="$__NET"
    __SRV_B_ALLOWED_IPS="$PREFIX"
    __SRV_B_PORT="$__CURR_SRV_B_PORT"

    __SRV_A_ENDPOINT="$SRV_A_IP:$SRV_A_PORT"

    __SRV_B_PRIVKEY=$(wg genkey)
    __SRV_B_PUBKEY=$(echo $__SRV_B_PRIVKEY | wg pubkey)

    # Append configuration for SRV A
cat <<EOF >> $SRV_A_OUTFILE
[Peer]
AllowedIPs = $__SRV_B_WG_IP
PublicKey = $__SRV_B_PUBKEY

EOF


    # Generate SRV B peer
cat <<EOF >> $__SRV_B_SECRETS_FILE
  wg$__INDEX.conf: |
    [Interface]
    Address = $__SRV_B_WG_IP
    ListenPort = $__SRV_B_PORT
    PrivateKey = $__SRV_B_PRIVKEY
    MTU = $MTU
    [Peer]
    AllowedIPs = $PREFIX
    Endpoint = $__SRV_A_ENDPOINT
    PublicKey = $__SRV_A_PUBKEY
    PersistentKeepalive = 60
EOF
    __CURR_SRV_B_PORT=$(($__CURR_SRV_B_PORT+1))
    __INDEX=$(($__INDEX+1))
done
