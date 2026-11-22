#!/usr/bin/env bash
# Creates the k3d cluster (if missing) and deploys the k8s observability lab:
# cert-manager, gateway (1 replica) -> httpbin + podinfo(TLS), scraped by
# Prometheus, visualized in Grafana. Safe to re-run: it just re-applies.
#
#   GW_IMAGE=nocleye/api-gateway:latest ./up.sh
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER="${CLUSTER:-nocleye-obs}"
NS=nocleye-obs
GW_IMAGE="${GW_IMAGE:-nocleye/api-gateway:v0.6.0-beta}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.21.3}"

for bin in docker k3d kubectl openssl; do
  command -v "$bin" >/dev/null || { echo "missing: $bin" >&2; exit 1; }
done

if k3d cluster list "$CLUSTER" >/dev/null 2>&1; then
  echo "cluster $CLUSTER already exists, re-applying"
  k3d cluster start "$CLUSTER" >/dev/null
else
  # host port -> NodePort: gateway 8501, support 8581, Prometheus 9590, Grafana 3500
  k3d cluster create "$CLUSTER" \
    --agents 1 \
    --k3s-arg "--disable=traefik@server:*" \
    -p "8501:30501@server:0" \
    -p "8581:30581@server:0" \
    -p "9590:30590@server:0" \
    -p "3500:30500@server:0" \
    --wait
fi
kubectl config use-context "k3d-$CLUSTER" >/dev/null
KC=(kubectl --context "k3d-$CLUSTER")

echo "installing cert-manager $CERT_MANAGER_VERSION"
"${KC[@]}" apply -f "https://github.com/cert-manager/cert-manager/releases/download/$CERT_MANAGER_VERSION/cert-manager.yaml" >/dev/null
"${KC[@]}" -n cert-manager wait deployment --all --for=condition=Available --timeout=180s

"${KC[@]}" apply -f "$LAB_DIR/manifests/namespace.yaml"

# JWT signing keys for the auth routes, shared by the gateway and the Locust
# job. Created once, so tokens stay valid across re-runs.
if ! "${KC[@]}" -n "$NS" get secret gw-jwt >/dev/null 2>&1; then
  "${KC[@]}" -n "$NS" create secret generic gw-jwt \
    --from-literal=hs256.key="$(openssl rand -hex 32)" \
    --from-literal=hs512.key="$(openssl rand -hex 64)"
fi

echo "gateway image: $GW_IMAGE"
# The cert-manager webhook can take a few seconds to accept requests after its
# Deployment is Available, so retry the apply a few times.
for i in 1 2 3 4 5 6; do
  if "${KC[@]}" kustomize "$LAB_DIR" \
      | sed "s|image: nocleye/api-gateway:v0.6.0-rc2.*|image: $GW_IMAGE|" \
      | "${KC[@]}" apply -f -; then
    break
  fi
  [[ $i -eq 6 ]] && exit 1
  echo "apply failed, retrying in 5s"; sleep 5
done

"${KC[@]}" -n "$NS" wait certificate/podinfo --for=condition=Ready --timeout=120s
for d in httpbin podinfo gateway prometheus grafana; do
  "${KC[@]}" -n "$NS" rollout status "deployment/$d" --timeout=180s
done

cat <<INFO

Lab is up (cluster $CLUSTER, namespace $NS, image $GW_IMAGE)
  gateway     http://localhost:8501   (e.g. curl localhost:8501/a/open/status/200)
  support     http://localhost:8581   (/metrics, /healthz, /readyz, token lab-token)
  prometheus  http://localhost:9590
  grafana     http://localhost:3500   (anonymous admin, "Gateway k8s Observability Lab")

Traffic:  $LAB_DIR/traffic.sh            (Locust job, see traffic.sh -h)
Logs:     kubectl -n $NS logs -f -l app=gateway --prefix
Stop:     $LAB_DIR/down.sh
INFO
