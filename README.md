<p align="center">
  <img src="assets/logo.png" alt="Nocleye logo" width="160">
</p>

# Nocleye

- Site: [Nocleye](https://nocleye.com) 
- Docs: [Docs](https://nocleye.com/docs)

---

This repository is where we share what we ship: release notes, links to artifacts, helper utilities and examples.

## API Gateway

A self-hosted API gateway that sits in front of your backend services. One YAML file describes which service gets which request, who the caller is, how much they can call, and which headers get through.

- **Servers and routes:** map public paths to backends, rewrite paths, reach HTTPS backends with your own CA. Proxies gRPC and WebSocket next to REST.
- **Header rules:** choose what is forwarded, removed or added.
- **Client identification:** identify callers by IP, bearer token, API key query parameter, custom header or custom query string.
- **Usage control:** rate limits per global, server or route scope, stackable, with burst control and an optional Redis-compatible shared store.
- **Authentication:** validate signed JWTs, OAuth2 tokens (JWKS or introspection) and encrypted JWE tokens, and require scopes, before a request reaches your backend.
- **Config check:** `nocleye check` validates your config and lists every error and warning before anything runs.
- **Observability:** JSON access log, Prometheus metrics, health probes, and a support server with a live config API.

Everything is defined once and bound by name, so the same rule can be reused anywhere in the config. Full details are in the [documentation](https://nocleye.com/docs/).

### Quick start

```bash
docker pull nocleye/api-gateway:v0.6.0-beta
# write gateway.yaml, then:
docker run --rm -v "$PWD/gateway.yaml:/etc/nocleye-beta/gateway/gateway.yaml:ro" \
  -e GATEWAY_CONFIG_PATH=gateway.yaml nocleye/api-gateway:v0.6.0-beta check
```

The [Getting started guide](https://nocleye.com/docs/getting-started/) has a minimal config and the run command.

## Beta

The gateway is under heavy change and we are aiming for a stable release in a few months. Until then:

1. We deliver in this order: **Security -> Ergonomics -> New Features -> Then performance.**
2. Backwards compatibility is not a goal yet, and docs are not versioned.
3. Supported platforms: **Linux and macOS.** Windows is not planned for now.
4. Docs are in English, with Brazilian Portuguese as time allows. The docs repository becomes public with the first stable release, so more languages can be added.


## Get it

Latest: **v0.6.0-beta** (2026-11-22)

| | |
|---|---|
| Downloads and verification | [nocleye.com/docs/releases](https://nocleye.com/docs/releases/) |
| Docker image | [`nocleye/api-gateway`](https://hub.docker.com/r/nocleye/api-gateway) |

## In this repository

- [`releases/`](releases/): release notes and links to artifacts.
- [`examples/`](examples/): usage examples.
- [`lab/`](lab/): a local Kubernetes (k3d) lab: the gateway in front of two sample apps, with Prometheus, a Grafana dashboard and Locust traffic scenarios.
- Utilities for working with the binaries and images will be added here as they are ready.

## Feedback and support

Use GitHub issues for anything public:

- [Report a bug](https://github.com/nocleye/api-gateway/issues/new?template=bug_report.yml)
- [Request a feature](https://github.com/nocleye/api-gateway/issues/new?template=feature_request.yml)
- [Ask a question](https://github.com/nocleye/api-gateway/issues/new?template=question.yml)

**Security issues:** please do not open a public issue. Email **[contact@nocleye.com](mailto:contact@nocleye.com)** instead (see [SECURITY.md](.github/SECURITY.md)).

For anything else, or just to say hi, write to [contact@nocleye.com](mailto:contact@nocleye.com).


Made by [Nocleye](https://nocleye.com)