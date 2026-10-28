# Hello gateway: one backend, two routes


### *Gateway Version used in this Tutorial v0.1.0-beta*

This is a small tutorial for showing the basics of how to use the api gateway

You will see:

- a server and two routes, and how the longest matching path wins,
- a path rewrite with `RemovePathPatternFromFinalRoute` and `AddPrefixToFinalRoute`,
- the `404` the gateway returns when no route matches,
- the headers the gateway adds before the request reaches your backend,


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

Rules:
  MetricsRules:
    # this controls the access log behavior    
    metrics-on:
      Enabled: true

GlobalConfig:
  MetricsRule: metrics-on

ServerConfigs:
  hello-app:
    URL: "http://app:8000"

ServerRoutes:
  echo:
    TargetServer: hello-app # this refers to the name you registered on <ServerConfigs> 
    PathPattern: /echo # this is how we want the server to be selected as destination when the request comes

  echo-v2:
    TargetServer: hello-app
    PathPattern: /echo/v2
    # this controls the removal of the PathPattern you chose match, if yes when routing we will remove the prefix
    # e.g full path as /echo/v2/items -> the backend will receive only /items
    RemovePathPatternFromFinalRoute: true
    
    # This allow you to add a prefix path to the final route, works similar as previous example but adding
    # e.g full path as /items -> the backend will receive /echo/latest/items
    AddPrefixToFinalRoute: /echo/latest
```

- A **server** is a backend the gateway can forward to. `hello-app` points to the `app` service of the compose file, which you will write in step 5.
- A **route** maps a public path to one server. A request matches a route when its path starts with `PathPattern`. When several routes match, the longest `PathPattern` wins.

Since there's no header, client ID or usage control rules here, so every header is forwarded and callers are identified by IP. See [servers and routes](https://nocleye.com/docs/servers-and-routes/) for the full reference.

## 4. Check the config

Validate the file before you run anything. `nocleye check` reads the config and lists what is wrong with it, without starting the gateway:

```sh
docker run \
  -v "$PWD/gateway.yaml:/etc/nocleye-beta/gateway/gateway.yaml:ro" \
  nocleye/api-gateway:v0.1.0-beta check --gConfigPath gateway.yaml
```

The config file is always read from `/etc/nocleye-beta/gateway/` inside the container, which is why the file is mounted there and `--gConfigPath` is only its name.

Expected output:

```bash
Checking gateway.yaml

WARNINGS (4)
  1. No auth method defined
     Fix:   Every route is publicly accessible. Add an entry under AuthMethods if you need protection.
  2. No client id rules defined
     Fix:   Clients will be identified by IP. Add a rule under Rules > ClientIDRules to use something else.
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

The cli, will be your best friend while using nocleye api gateway! We are putting a lot of effort on it to prevent as much errors as possible, so we share with you in advance everytime you made a mistake or missed something.


## 5. Docker compose
Let's put everything together now (I hope you have changed back the routes to their expected paths :) )

`docker-compose.yml`:

```yaml
services:
  gateway:
    image: nocleye/api-gateway:v0.1.0-beta
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

# expected to see something like this
{
  "method": "GET",
  "path": "/echo/hello",
  "query": "",
  "headers": {
    "Host": "app:8000",
    "User-Agent": "curl/8.18.0",
    "Accept": "*/*",
    "Traceparent": "00-de51182f84f254f30f2f497500223d31-0db0b7bd8aa15c31-01",
    "X-Forwarded-For": "172.18.0.1",
    "X-Forwarded-Host": "localhost:8080",
    "X-Forwarded-Proto": "http",
    "X-Nocleye-Request-Id": "01a18487-bb2b-74c1-880e-021b98176f28",
    "Accept-Encoding": "gzip"
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
    "Traceparent": "00-fe58cfeb391d2334fe8d53d374794625-33c785d202ae885f-01",
    "X-Forwarded-For": "172.18.0.1",
    "X-Forwarded-Host": "localhost:8080",
    "X-Forwarded-Proto": "http",
    "X-Nocleye-Request-Id": "01a1848b-fcc3-7397-8d88-49652b630e77",
    "Accept-Encoding": "gzip"
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
    "Traceparent": "00-383f32ae8036fe9cf16e12403787a15c-7ab4864c5d261a60-01",
    "X-Forwarded-For": "172.18.0.1",
    "X-Forwarded-Host": "localhost:8080",
    "X-Forwarded-Proto": "http",
    "X-Nocleye-Request-Id": "01a1848b-26c4-73ea-b437-8a4212d70051",
    "Accept-Encoding": "gzip"
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
X-Nocleye-Request-Id: 01a1848e-0dea-7051-be7c-a0c9c84c7b25
Date: Wed, 28 Oct 2026 22:07:44 GMT
Content-Length: 13
Content-Type: text/plain; charset=utf-8

API NOT FOUND
```

## 8. Clean up

```sh
docker compose down
```

## Next steps

- [Header rules](https://nocleye.com/docs/header-rules/): choose which headers reach the backend.
- [Usage control](https://nocleye.com/docs/usage-control/): rate limits per caller.
- [Authentication](https://nocleye.com/docs/authentication/): validate JWT tokens at the gateway.
- [Logs and metrics](https://nocleye.com/docs/observability/): Prometheus metrics and health probes.


I hope you understand everything, if you have any questions please, email us on support@nocleye.com.
Now I have to go, I have a bug to fix :)
