# Hello gateway: one backend, two routes


### *Gateway Version used in this Tutorial v0.5.0-beta*

This is a small tutorial for showing the basics of how to use the api gateway

You will see:

- a server and two routes, and how the longest matching path wins,
- a path rewrite with `RemovePathPattern` and `AddPathPrefix`,
- the `404` the gateway returns when no route matches,
- the headers the gateway adds before the request reaches your backend,
- the gateway log and the access log, to see what the gateway did with each request.


## Required tools

- Docker with Compose
- `curl`

---


### 1. The backend

Let's start with our backend! The backend is a tiny echo API. It answers every request with the method, path, query string and headers it received, so each effect of the gateway is visible with plain `curl`. It only uses the Python standard library.

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
Now, to run our example inside the docker-compose we will need a docker file.

`app/Dockerfile`:

```dockerfile
FROM python:3.14-slim

WORKDIR /app
COPY app.py .

EXPOSE 8000
CMD ["python", "app.py"]
```

### 3. The gateway config
It's time for the gateway configuration! For our example, we will need one server registered and 2 routes. 

`gateway.yaml`:

```yaml
ApiVersion: v1Beta

ServerConfigs:
  hello-app:
    URL: "http://app:8000"

ServerRoutes:
  echo:
    TargetServer: hello-app # this refers to the name you registered on <ServerConfigs> 
    MatchOptions:
      PathPattern: /echo # this is how we want the server to be selected as destination when the request comes

  echo-v2:
    TargetServer: hello-app
    MatchOptions:
      PathPattern: /echo/v2
    BeforeForwarding:
      # this controls the removal of the PathPattern you chose match, if yes when routing we will remove the prefix
      # e.g full path as /echo/v2/items -> the backend will receive only /items
      RemovePathPattern: true

      # This allow you to add a prefix path to the final route, works similar as previous example but adding
      # e.g full path as /items -> the backend will receive /echo/latest/items
      AddPathPrefix: /echo/latest
```

- A **server** is a backend the gateway can forward to. `hello-app` points to the `app` service of the compose file, which you will write in step 5.
- A **route** maps a public path to one server. A request matches a route when its path starts with `PathPattern`. When several routes match, the longest `PathPattern` wins.

Since there's no header, client ID or usage control rules here, every header is forwarded and callers are not identified, which only matters once you add usage control. The access log needs no config: every request is logged by default. See [servers and routes](https://nocleye.com/docs/servers-and-routes/) for the full reference.

## 4. Check the config

Validate the file before you run anything. `nocleye check` reads the config and lists what is wrong with it, without starting the gateway:

```sh
docker run \
  -v "$PWD/gateway.yaml:/etc/nocleye-beta/gateway/gateway.yaml:ro" \
  nocleye/api-gateway:v0.5.0-beta check --gConfigPath gateway.yaml
```

The config file is always read from `/etc/nocleye-beta/gateway/` inside the container, which is why the file is mounted there and `--gConfigPath` is only its name.

Expected output:

```bash
Checking gateway.yaml

WARNINGS (4)
  1. No auth method defined
     Fix:   Every route is publicly accessible. Add an entry under AuthMethods if you need protection.
  2. No client id rules defined
     Fix:   Callers of routes without an auth method are not identified, so usage control can't limit them. Add a rule under Rules > ClientIDRules and bind it with ClientIDRule.
  3. No header rules defined
     Fix:   All headers from the user's request are forwarded. Add a rule under Rules > HeaderRules to restrict them.
  4. No usage control rules defined
     Fix:   Clients won't be limited at all. Add a rule under Rules > UsageControlRules if you want limits.

Found 1 server, 2 routes and 0 auth methods.

✓ Config is valid with 4 warnings. Warnings don't stop the gateway from starting.
Only the file structure is checked; key files and backend reachability are verified when the gateway starts.
```

The cli available in the gateway bin has a lot of built-in helpers commands that you can check later. But let's test the `check` command.

Update your `gateway.yaml` so both routes are equal as `/echo` and run the same command again.
You will an error like this:

```bash
Checking gateway.yaml

ERRORS (1)
  1. Two routes use the same PathPattern
     Where: routes echo and echo-v2, path /echo
     Fix:   Give each route its own PathPattern, or remove the duplicate.

WARNINGS (4)
  ... <Omited same as before>

✗ 1 error, 4 warnings. The gateway will not start with this config.
Only the file structure is checked; key files and backend reachability are verified when the gateway starts.
```

The report is always printed, and when the config has at least one error the command also exits with a failure (exit code `1`; with the config valid it is `0`, warnings alone don't change it). That makes `nocleye check` usable as a gate in a script or a CI job: `docker run ... check --gConfigPath gateway.yaml || echo "config rejected"`.

The cli, will be your best friend while using nocleye api gateway! We are putting a lot of effort on it to prevent as much errors as possible, so we share with you in advance everytime you made a mistake or missed something.


## 5. Docker compose
Let's put everything together now (I hope you have changed back the routes to their expected paths :) )

`docker-compose.yml`:

```yaml
services:
  gateway:
    image: nocleye/api-gateway:v0.6.0-beta
    ports:
      - "8080:8080"
    environment:
      # part of the gateway args can be also used as an env var      
      GATEWAY_CONFIG_PATH: gateway.yaml
    volumes:
      - ./gateway.yaml:/etc/nocleye-beta/gateway/gateway.yaml:ro
    depends_on:
      - app

  # No published port: the only way to reach it is through the gateway.
  app:
    build: ./app
```

Only the gateway publishes a port.

## 6. Run it

```sh
docker compose up --build
```

Open a new terminal and send a first request:

```sh
curl -s localhost:8080/echo/hello

# expected to see something like this. The gateway added the Traceparent, X-Forwarded-* and X-Nocleye-* headers;
# X-Nocleye-Authenticated is "false" because this route has no authentication method.
{
  "method": "GET",
  "path": "/echo/hello",
  "query": "",
  "headers": {
    "Host": "app:8000",
    "User-Agent": "curl/8.18.0",
    "Accept": "*/*",
    "Traceparent": "00-f64e4dea3173b72ccd5625d6b822b5d3-db5be6f0d98682d2-01",
    "X-Forwarded-For": "172.18.0.1",
    "X-Forwarded-Host": "localhost:8080",
    "X-Forwarded-Proto": "http",
    "X-Nocleye-Authenticated": "false",
    "X-Nocleye-Request-Id": "01a2093b-7237-755a-aa42-92b88dac1ee0"
  },
  "body": ""
}
```

## 7. Try the routes

### A route without rewrite

```sh
curl -s "localhost:8080/echo/hello?name=world"

# The backend received `/echo/hello`, the same path the caller used, and the query string.
{
  "method": "GET",
  "path": "/echo/hello",
  "query": "name=world",
  "headers": {
    "Host": "app:8000",
    "User-Agent": "curl/8.18.0",
    "Accept": "*/*",
    "Traceparent": "00-ad37e3cab0d769390dd50942dbc752a3-42b8b8d660f1e6b9-01",
    "X-Forwarded-For": "172.18.0.1",
    "X-Forwarded-Host": "localhost:8080",
    "X-Forwarded-Proto": "http",
    "X-Nocleye-Authenticated": "false",
    "X-Nocleye-Request-Id": "01a2093c-b3fc-78db-9cee-463a1d46a634"
  },
  "body": ""
}
```



### The longest route wins, and the path is rewritten

```sh
curl -s "localhost:8080/echo/v2/items?page=2"

# `/echo/v2/items` matches both routes. `echo-v2` has the longer `PathPattern`, so it wins: `/echo/v2` is removed and `/echo/latest` is added. 
# Look at `path` and `query` in the output, the backend received `/echo/latest/items?page=2`.
{
  "method": "GET",
  "path": "/echo/latest/items",
  "query": "page=2",
  "headers": {
    "Host": "app:8000",
    "User-Agent": "curl/8.18.0",
    "Accept": "*/*",
    "Traceparent": "00-4e8f138f011dca0d3cdf1ecec13e4447-214d01be959ac922-01",
    "X-Forwarded-For": "172.18.0.1",
    "X-Forwarded-Host": "localhost:8080",
    "X-Forwarded-Proto": "http",
    "X-Nocleye-Authenticated": "false",
    "X-Nocleye-Request-Id": "01a2093d-0106-7811-b6d0-d2440e1c6479"
  },
  "body": ""
}
```

### No route matches

```sh
curl -si localhost:8080/nope

# You should see something like this.
HTTP/1.1 404 Not Found
X-Content-Type-Options: nosniff
X-Nocleye-Request-Id: 01a2093d-a8da-7760-a15e-9822a168f83f
Date: Mon, 23 Nov 2026 16:29:25 GMT
Content-Length: 13
Content-Type: text/plain; charset=utf-8

API NOT FOUND
```

## 8. Read the logs

The gateway writes two kinds of logs. Both show up in `docker compose logs`:

```sh
docker compose logs gateway --no-log-prefix
```

The **gateway log** (standard error) tells what the gateway itself is doing. On startup you will see the same warnings `nocleye check` gave you, and that it is listening:

```json
...
{"level":"warn","stream":"gateway","version":"v0.6.0-beta","component":"LoadGatewayConfig","time":"2026-11-23T16:26:20.452Z","caller":"run.go:108","message":"Gateway config warning: no header rules defined. It will forward all headers from users request"}
{"level":"warn","stream":"gateway","version":"v0.6.0-beta","component":"LoadGatewayConfig","time":"2026-11-23T16:26:20.452Z","caller":"run.go:108","message":"Gateway config warning: no client id rules defined. Callers of routes without authentication are not identified"}
{"level":"warn","stream":"gateway","version":"v0.6.0-beta","component":"LoadGatewayConfig","time":"2026-11-23T16:26:20.452Z","caller":"run.go:108","message":"Gateway config warning: UsageControlRule: empty. The gateway will have zero restrictions of usage"}
{"level":"warn","stream":"gateway","version":"v0.6.0-beta","component":"LoadGatewayConfig","time":"2026-11-23T16:26:20.452Z","caller":"run.go:108","message":"Gateway config warning: no auth method defined. All routes will be for public access"}
{"level":"info","stream":"gateway","version":"v0.6.0-beta","component":"Gate","time":"2026-11-23T16:26:20.452Z","caller":"gate.go:97","message":"Loading gate configuration"}
{"level":"info","stream":"gateway","version":"v0.6.0-beta","component":"Initializer","gateway_id":"1","access_log_sinks":["stdout"],"support_address":"127.0.0.1:8081","prometheus_enabled":false,"prometheus_metrics":["requests","streams","auth","dependencies","access_log","gateway","usage_control"],"support_token":"unset","time":"2026-11-23T16:26:20.453Z","caller":"run.go:339","message":"gateway started"}
{"level":"info","stream":"gateway","version":"v0.6.0-beta","component":"RunGatewayServer","time":"2026-11-23T16:26:20.453Z","caller":"run.go:124","message":"Starting Gateway server on addr: 0.0.0.0:8080"}
{"level":"warn","stream":"gateway","version":"v0.6.0-beta","component":"RunGatewayServer","time":"2026-11-23T16:26:20.453Z","caller":"run.go:165","message":"Gateway starting with TLS disabled"}
{"level":"info","stream":"gateway","version":"v0.6.0-beta","component":"RunSupportServer","time":"2026-11-23T16:26:20.453Z","caller":"run.go:207","message":"Starting Support server on addr: 127.0.0.1:8081"}
```

The startup also logs a few more `info` lines (access log started, support server address, ...), they were left out here.

The **access log** (standard output) has one JSON line per request, with the `stream` field set to `access`. Lines are written in batches, so a line can show up a second or so after the request. Here are the lines for `/echo/v2/items?page=2` and `/nope`:

```json
{"stream":"access","ts":"2026-11-23T16:28:42.630Z","request_path":"/echo/v2/items","request_method":"GET","response_status":200,"error_reason":"","caller_ip":"172.18.0.1","caller_id":"","request_id":"","nocleye_request_id":"01a2093d-0106-7811-b6d0-d2440e1c6479","auth_method":"","request_size_bytes":0,"response_size_bytes":483,"upstream_service":"hello-app","upstream_latency_ms":1.101,"latency_ms":1.129,"user_agent":"curl/8.18.0","path_pattern":"/echo/v2","header_match":"","route_matched":"echo-v2","gateway_version":"v0.6.0-beta","upstream_path":"/echo/latest/items"}
{"stream":"access","ts":"2026-11-23T16:29:25.594Z","request_path":"/nope","request_method":"GET","response_status":404,"error_reason":"API NOT FOUND","caller_ip":"172.18.0.1","caller_id":"","request_id":"","nocleye_request_id":"01a2093d-a8da-7760-a15e-9822a168f83f","auth_method":"","request_size_bytes":0,"response_size_bytes":13,"upstream_service":"","upstream_latency_ms":0,"latency_ms":0.019,"user_agent":"curl/8.18.0","path_pattern":"","header_match":"","route_matched":"","gateway_version":"v0.6.0-beta"}
```

- `route_matched` shows which route won, `echo-v2` for the first request and empty for the second, because no route matched. `error_reason` says why the gateway itself refused it.
- `nocleye_request_id` is the same value the backend received in the `X-Nocleye-Request-Id` header, so you can follow one request from the gateway to your backend.
- `response_size_bytes` is the size of the body sent back to the caller. `caller_id`, `request_id` and `auth_method` are empty because there is no authentication and no client ID rule here.

Use `docker compose logs gateway --no-log-prefix | grep '"stream":"access"'` to see only the access log.

## 9. Clean up

```sh
docker compose down
```

## Next steps

- [Header rules](https://nocleye.com/docs/header-rules/): choose which headers reach the backend.
- [Usage control](https://nocleye.com/docs/usage-control/): rate limits per caller.
- [Authentication](https://nocleye.com/docs/authentication/): validate JWT tokens at the gateway.
- [Logs and metrics](https://nocleye.com/docs/observability/): Prometheus metrics and health probes.


I hope you understand everything, if you have any questions, bug to report or feature to request:
- [Report a bug](https://github.com/nocleye/api-gateway/issues/new?template=bug_report.yml)
- [Request a feature](https://github.com/nocleye/api-gateway/issues/new?template=feature_request.yml)
- [Ask a question](https://github.com/nocleye/api-gateway/issues/new?template=question.yml)

See you soon :)
