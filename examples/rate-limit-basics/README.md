# Rate limit basics: one global limit, two routes

### *Gateway Version used in this Tutorial v0.4.0-beta*

This tutorial shows how the usage control (rate limit) of the api gateway works, and how the `Cascade` and `Strict` modes change which limits a route has to respect.

You will see:

- a client ID rule and why a rate limit needs one,
- a global limit applied to every route,
- a route in `Cascade` mode (the default): the global limit and the route limit both apply,
- a route in `Strict` mode: only the route limit applies,
- the `429` the gateway returns when a limit is exceeded, and how it looks in the access log.

If you did not follow [hello-gateway](../hello-gateway/) yet, start there, this tutorial reuses the same backend.


## Required tools

- Docker with Compose
- `curl`

---


### 1. The backend

The backend is the same tiny echo API of the hello-gateway tutorial. It answers every request with the method, path, query string and headers it received. It only uses the Python standard library.

`app/app.py`:

```python
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class Echo(BaseHTTPRequestHandler):
    def handle_any(self):
        url = urlsplit(self.path)
        length = int(self.headers.get("Content-Length") or 0)
        body = {
            "method": self.command,
            "path": url.path,
            "query": url.query,
            "headers": {k: v for k, v in self.headers.items()},
            "body": self.rfile.read(length).decode(errors="replace"),
        }
        payload = json.dumps(body, indent=2).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = handle_any


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8000), Echo).serve_forever()
```

### 2. Its Dockerfile

`app/Dockerfile`:

```dockerfile
FROM python:3.14-slim

WORKDIR /app
COPY app.py .

EXPOSE 8000
CMD ["python", "app.py"]
```

### 3. The gateway config

A rate limit has three pieces: **who** is counted, **how many** requests are allowed, and **where** the limit applies.

`gateway.yaml`:

```yaml
ApiVersion: v1Beta

Rules:
  # who is counted: here the caller's IP
  ClientIDRules:
    by-ip:
      Modes: [IP]

  UsageControlRules:
    # 5 requests per minute for each caller
    global-limit:
      RequestCount: 5
      WindowTime: 1m
    # 10 requests per minute for each caller
    route-limit:
      RequestCount: 10
      WindowTime: 1m

GlobalConfig:
  ClientIDRule: by-ip
  UsageControlRules: [global-limit]

ServerConfigs:
  hello-app:
    URL: "http://app:8000"

ServerRoutes:
  # Cascade (default): global-limit AND route-limit both apply, the stricter one wins -> 5 requests
  cascade:
    TargetServer: hello-app
    MatchOptions:
      PathPattern: /cascade
    UsageControlRules: [route-limit]

  # Strict: only route-limit applies, global-limit is ignored -> 10 requests
  strict:
    TargetServer: hello-app
    MatchOptions:
      PathPattern: /strict
    UsageControlMode: Strict
    UsageControlRules: [route-limit]
```

- A **client ID rule** decides how the gateway tells callers apart. Each caller has its own count. `Modes: [IP]` identifies the caller by its IP address. There is no default rule, so without one the gateway cannot count anybody (you will see this error in the next step).
- A **usage control rule** says how many requests (`RequestCount`) are allowed in a period (`WindowTime`). Defining a rule does nothing by itself, it has to be bound by name.
- Rules bound in `GlobalConfig` apply to every route. Rules bound in a route apply to that route (and rules bound in a server to all its routes).
- `UsageControlMode` chooses which of those scopes are checked:

| Mode | Limits checked on the route | Requests allowed per minute here |
|---|---|---|
| `Cascade` (default) | global **and** route, the request must pass every one | 5 (the global limit is reached first) |
| `Strict` | only the route's, global rules are ignored | 10 |

Both routes bind the very same `route-limit`, the only difference between them is the mode. See [usage control](https://nocleye.com/docs/usage-control/) and [client ID rules](https://nocleye.com/docs/client-id-rules/) for the full reference.

## 4. Check the config

Validate the file before you run anything:

```sh
docker run \
  -v "$PWD/gateway.yaml:/etc/nocleye-beta/gateway/gateway.yaml:ro" \
  nocleye/api-gateway:v0.4.0-beta check --gConfigPath gateway.yaml
```

Expected output:

```bash
Checking gateway.yaml

WARNINGS (2)
  1. No auth method defined
     Fix:   Every route is publicly accessible. Add an entry under AuthMethods if you need protection.
  2. No header rules defined
     Fix:   All headers from the user's request are forwarded. Add a rule under Rules > HeaderRules to restrict them.

Found 1 server, 2 routes and 0 auth methods.

✓ Config is valid with 2 warnings. Warnings don't stop the gateway from starting.
Only the file structure is checked; key files and backend reachability are verified when the gateway starts.
```

Notice that, unlike in hello-gateway, there are no warnings about client id rules or usage control: you have both now.

Let's break it on purpose. Remove the line `ClientIDRule: by-ip` from `GlobalConfig` and run the same command again. You will see an error like this:

```bash
Checking gateway.yaml

ERRORS (3)
  1. Global usage control can't run on some routes
     Where: hello-app/cascade
     Fix:   Add an auth method or a client ID rule (Modes, e.g. IP) that applies to it: on the route, its server or GlobalConfig. Otherwise the limit never runs. Listed server/route pairs are the ones to fix.
  2. Route has usage control but no way to identify callers
     Where: route cascade
     Fix:   Add an auth method or a client ID rule (Modes, e.g. IP) that applies to it: on the route, its server or GlobalConfig. Otherwise the limit never runs.
  3. Route has usage control but no way to identify callers
     Where: route strict
     Fix:   Add an auth method or a client ID rule (Modes, e.g. IP) that applies to it: on the route, its server or GlobalConfig. Otherwise the limit never runs.

WARNINGS (2)
  ... <Omitted same as before>

✗ 3 errors, 2 warnings. The gateway will not start with this config.
Only the file structure is checked; key files and backend reachability are verified when the gateway starts.
```

The gateway refuses a limit it could never enforce. Note that `strict` is not listed in the first error, because a `Strict` route ignores the global rules. Put the line back before moving on.


## 5. Docker compose

`docker-compose.yml`:

```yaml
services:
  gateway:
    image: nocleye/api-gateway:v0.4.0-beta
    ports:
      - "8080:8080"
    environment:
      GATEWAY_CONFIG_PATH: gateway.yaml
    volumes:
      - ./gateway.yaml:/etc/nocleye-beta/gateway/gateway.yaml:ro
    depends_on:
      - app

  # No published port: the only way to reach it is through the gateway.
  app:
    build: ./app
```

## 6. Run it

```sh
docker compose up --build
```

## 7. Try the limits

Open a new terminal. This loop sends 8 requests to the `cascade` route and prints only the status code of each one:

```sh
for i in $(seq 1 8); do curl -s -o /dev/null -w "%{http_code} " localhost:8080/cascade/ping; done; echo

# 5 requests pass, the global limit (5 per minute) is reached
200 200 200 200 200 429 429 429
```

Now the `strict` route, with 12 requests:

```sh
for i in $(seq 1 12); do curl -s -o /dev/null -w "%{http_code} " localhost:8080/strict/ping; done; echo

# 10 requests pass: the global limit is ignored here, only route-limit (10 per minute) counts
200 200 200 200 200 200 200 200 200 200 429 429
```

Same `route-limit`, different result: that is the effect of `Cascade` versus `Strict`.

This is what a rejected request looks like:

```sh
curl -si localhost:8080/cascade/ping

HTTP/1.1 429 Too Many Requests
X-Content-Type-Options: nosniff
X-Nocleye-Request-Id: 01a1bc19-80c2-7c62-89e7-fcdf0045014c
Date: Sun, 08 Nov 2026 16:59:10 GMT
Content-Length: 17
Content-Type: text/plain; charset=utf-8

Too many requests
```

The request was refused by the gateway, it never reached the backend. The limits are per minute, so wait a minute to try again, or restart the gateway to reset every count:

```sh
docker compose restart gateway
```

## 8. Read the logs

Every request is written to the access log (standard output), including the rejected ones:

```sh
docker compose logs gateway --no-log-prefix | grep '"stream":"access"'
```

A request that passed, and one that was limited:

```json
{"stream":"access","ts":"2026-11-08T16:59:10.295Z","request_path":"/cascade/ping","request_method":"GET","response_status":200,"error_reason":"","caller_ip":"172.18.0.1","upstream_service":"hello-app","upstream_latency_ms":1.288,"route_matched":"cascade", ...}
{"stream":"access","ts":"2026-11-08T16:59:10.323Z","request_path":"/cascade/ping","request_method":"GET","response_status":429,"error_reason":"Too many requests","caller_ip":"172.18.0.1","upstream_service":"hello-app","upstream_latency_ms":0,"route_matched":"cascade", ...}
```

- `response_status` is `429` and `error_reason` says `Too many requests`, which tells you the gateway itself refused the request.
- `upstream_latency_ms` is `0`: the backend was never called.
- `caller_ip` is the one being counted by the `by-ip` rule.

The lines above were shortened (`...`), you will see a few more fields.

## 9. Clean up

```sh
docker compose down
```

## Next steps

- [Usage control](https://nocleye.com/docs/usage-control/): burst, several rules per scope and server level limits.
- [Client ID rules](https://nocleye.com/docs/client-id-rules/): count callers by API key, header or token instead of IP.
- [Authentication](https://nocleye.com/docs/authentication/): validate tokens at the gateway.
- [Logs and metrics](https://nocleye.com/docs/observability/): Prometheus metrics and health probes.
