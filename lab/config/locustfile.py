"""Locust scenarios for the k8s observability lab, run by traffic.sh as a Job.

One User class per scenario; pick them on the command line, e.g.
  ./traffic.sh SteadyUser ErrorsUser
Routes mirror config/gateway.yaml (svc-a = go-httpbin, svc-b = podinfo).
JWT keys come from the gw-jwt Secret, mounted at /jwt.
"""
import random
import string
import time
from pathlib import Path

import jwt
from locust import FastHttpUser, between, task

KEYS = Path("/jwt")


def token(alg: str, key_file: str) -> str:
    now = int(time.time())
    key = (KEYS / key_file).read_bytes().strip()
    return jwt.encode({"sub": "lab-user", "iat": now, "exp": now + 3600}, key, algorithm=alg)


def rand(k: int) -> str:
    return "".join(random.choices(string.ascii_letters + string.digits, k=k))


def fake_ip() -> str:
    return f"203.0.113.{random.randint(1, 254)}"


class SteadyUser(FastHttpUser):
    """Baseline browsing: fast and slow 2xx on both upstreams."""
    wait_time = between(0.5, 1.5)

    @task(4)
    def httpbin(self):
        self.client.get("/a/open/get")

    @task(2)
    def podinfo(self):
        # svc-b has a server-wide limit (50/min) shared with RateLimitUser, so 429 is expected
        with self.client.get(random.choice(["/b/open/", "/b/open/version"]), name="/b/open/*",
                             catch_response=True) as r:
            if r.status_code == 429:
                r.success()

    @task(2)
    def delay(self):
        self.client.get(f"/a/open/delay/{random.choice(['50ms', '800ms'])}", name="/a/open/delay/*")

    @task(1)
    def headers(self):
        self.client.get("/a/open/headers")


class ErrorsUser(FastHttpUser):
    """4xx/5xx from the upstream, flaky responses and 502 from a dead server."""
    wait_time = between(0.5, 1.5)

    @task(2)
    def status(self):
        code = random.choice([400, 404, 500, 503])
        with self.client.get(f"/a/open/status/{code}", name="/a/open/status/*", catch_response=True) as r:
            r.success()

    @task(2)
    def unstable(self):
        with self.client.get("/a/open/unstable?failure_rate=0.3", name="/a/open/unstable", catch_response=True) as r:
            r.success()

    @task(1)
    def down(self):
        with self.client.get("/down/x", catch_response=True) as r:
            r.success()


class RateLimitUser(FastHttpUser):
    """Route/server limits and a lifetime quota, with a few noisy clients."""
    wait_time = between(0.1, 0.5)
    clients = [f"client-{i}" for i in range(30)]
    noisy = clients[:3]

    def client_id(self) -> str:
        # the 3 noisy clients get ~half the traffic, enough to hit limit-a-low and quota-a
        return random.choice(self.noisy * 10 + self.clients)

    def call(self, path: str, **headers):
        with self.client.get(path, headers=headers, catch_response=True) as r:
            if r.status_code == 429:
                r.success()

    @task
    def limited(self):
        self.call("/a/limited/get", **{"X-Client-Id": self.client_id()})

    @task
    def server_and_route_limited(self):
        self.call("/b/limited/version")

    @task
    def quota(self):
        self.call("/a/quota/get", **{"X-Client-Id": self.client_id()})


class AuthUser(FastHttpUser):
    """Valid HS256/HS512 tokens, missing tokens and garbage tokens."""
    wait_time = between(0.5, 1.5)

    def on_start(self):
        self.hs256 = token("HS256", "hs256.key")
        self.hs512 = token("HS512", "hs512.key")

    @task(4)
    def valid(self):
        self.client.get("/a/secure/get", headers={"Authorization": f"Bearer {self.hs256}"})
        # svc-b has a server-wide limit (50/min), so 429 is expected
        with self.client.get("/b/secure/version", headers={"X-Auth-Token": self.hs512},
                             catch_response=True) as r:
            if r.status_code == 429:
                r.success()

    @task(3)
    def missing(self):
        with self.client.get("/a/secure/get", name="/a/secure/get (no token)",
                             headers={"X-Forwarded-For": fake_ip()}, catch_response=True) as r:
            r.success() if r.status_code == 401 else r.failure(f"expected 401, got {r.status_code}")

    @task(3)
    def garbage(self):
        with self.client.get("/a/secure/get", name="/a/secure/get (bad token)",
                             headers={"Authorization": "Bearer garbage.garbage.garbage",
                                      "X-Forwarded-For": fake_ip()}, catch_response=True) as r:
            r.success() if r.status_code == 401 else r.failure(f"expected 401, got {r.status_code}")


class ScannerUser(FastHttpUser):
    """Probes for well-known paths, all unmatched."""
    wait_time = between(0.2, 1)
    guesses = ["/wp-admin", "/.env", "/.git/config", "/admin", "/phpmyadmin"]

    @task
    def probe(self):
        path = random.choice(self.guesses + ["/" + rand(8).lower()])
        with self.client.get(path, name="scanner", catch_response=True) as r:
            r.success()

