#!/usr/bin/env bash
# Runs Locust (config/locustfile.py) as a Job inside the cluster against the
# gateway Service and prints its summary when done.
#
#   ./traffic.sh [-u users] [-r spawn-rate] [-t duration] [UserClass ...]
#
# User classes: SteadyUser ErrorsUser RateLimitUser AuthUser ScannerUser
#               CardinalityUser (default: all but CardinalityUser)
# Examples:
#   ./traffic.sh -t 2m
#   ./traffic.sh -u 300 -r 100 -t 30s SteadyUser     # spike
#   ./traffic.sh CardinalityUser
set -euo pipefail

CLUSTER="${CLUSTER:-nocleye-obs}"
NS=nocleye-obs
LOCUST_IMAGE="${LOCUST_IMAGE:-locustio/locust:2.47.0}"
PYJWT_VERSION="${PYJWT_VERSION:-2.15.1}"
USERS=20 RATE=5 DURATION=60s

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
while getopts "u:r:t:h" opt; do
  case "$opt" in
    u) USERS="$OPTARG" ;;
    r) RATE="$OPTARG" ;;
    t) DURATION="$OPTARG" ;;
    h) usage ;;
    *) usage 1 ;;
  esac
done
shift $((OPTIND - 1))
CLASSES=("$@")
[[ ${#CLASSES[@]} -eq 0 ]] && CLASSES=(SteadyUser ErrorsUser RateLimitUser AuthUser ScannerUser)

KC=(kubectl --context "k3d-$CLUSTER" -n "$NS")
"${KC[@]}" delete job traffic --ignore-not-found --wait=true >/dev/null

echo "locust: ${USERS} users, spawn ${RATE}/s, ${DURATION}, classes: ${CLASSES[*]}"
"${KC[@]}" apply -f - >/dev/null <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: traffic
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels: {app: traffic}
    spec:
      restartPolicy: Never
      containers:
        - name: locust
          image: ${LOCUST_IMAGE}
          command: [sh, -c]
          args:
            - >-
              pip install -q --disable-pip-version-check --target /tmp/py pyjwt==${PYJWT_VERSION} &&
              PYTHONPATH=/tmp/py exec locust -f /locust/locustfile.py --headless
              --host http://gateway:8080 -u ${USERS} -r ${RATE} -t ${DURATION}
              --only-summary --exit-code-on-error 0 ${CLASSES[*]}
          volumeMounts:
            - {name: locustfile, mountPath: /locust, readOnly: true}
            - {name: jwt, mountPath: /jwt, readOnly: true}
      volumes:
        - name: locustfile
          configMap: {name: locustfile}
        - name: jwt
          secret: {secretName: gw-jwt}
YAML

"${KC[@]}" wait pod -l job-name=traffic --for=condition=Ready --timeout=120s >/dev/null 2>&1 \
  || "${KC[@]}" wait pod -l job-name=traffic --for=jsonpath='{.status.phase}'=Succeeded --timeout=5s >/dev/null 2>&1 || true
"${KC[@]}" logs -f job/traffic
