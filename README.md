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

- **Servers and routes:** map public paths to backends, rewrite paths, reach HTTPS backends with your own CA.
- **Header rules:** choose what is forwarded, removed or added.
- **Client identification:** identify callers by IP, token, header, cookie or query string.
- **Usage control:** rate limits per global, server or route scope, stackable.
- **Authentication:** validate signed JWT tokens before a request reaches your backend.
- **Observability:** JSON access log, Prometheus metrics, health probes.

Everything is defined once and bound by name, so the same rule can be reused anywhere in the config. Full details are in the [documentation](https://nocleye.com/docs/).

## Beta

The gateway is under heavy change and we are aiming for a stable release in a few months. Until then:

1. We deliver in this order: **Security -> Ergonomics -> New Features -> Then performance.**
2. Backwards compatibility is not a goal yet, and docs are not versioned.
3. Supported platforms: **Linux and macOS.** Windows is not planned for now.
4. Docs are in English, with Brazilian Portuguese as time allows. The docs repository becomes public with the first stable release, so more languages can be added.

Coming soon:

- [ ] Route by header
- [ ] New authentication options
- [ ] Database for the rate limit system

## Get it

Latest: **v0.1.0-beta** (2026-10-26)

| | |
|---|---|
| Downloads and verification | [nocleye.com/docs/releases](https://nocleye.com/docs/releases/) |
| Docker image | [`nocleye/api-gateway`](https://hub.docker.com/r/nocleye/api-gateway) |

## In this repository

- [`releases/`](releases/): release notes and links to artifacts.
- [`examples/`](examples/): usage examples.
- Utilities for working with the binaries and images will be added here as they are ready.

## Contact

Write to **[contact@nocleye.com](mailto:contact@nocleye.com)** to:

- ask for a feature,
- report a bug,
- report a security issue (please use email, not a public issue),
- or just say hi.


Made by [Nocleye](https://nocleye.com)