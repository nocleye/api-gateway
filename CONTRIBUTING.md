# Contributing

Thanks for helping improve the Nocleye examples and lab!

## What you can contribute

- Fixes and updates to the [`examples/`](examples/) and the [`lab/`](lab/).
- New examples.

Not open for contributions:

- [`releases/`](releases/): release notes are maintained by Nocleye.
- The gateway itself: its source is not public.

Found a bug in the gateway or have an idea for it? Open an issue instead:
[report a bug](https://github.com/nocleye/api-gateway/issues/new?template=bug_report.yml),
[request a feature](https://github.com/nocleye/api-gateway/issues/new?template=feature_request.yml) or
[ask a question](https://github.com/nocleye/api-gateway/issues/new?template=question.yml).

## Before you start

- **Small changes** (a typo, a broken command, an outdated output, a version bump): open a pull request directly.
- **A new example or a bigger lab change**: open a [feature request](https://github.com/nocleye/api-gateway/issues/new?template=feature_request.yml) first, so we can agree on it before you spend time writing it.
- **Security issues**: do not open an issue or a pull request. See [SECURITY.md](.github/SECURITY.md).

## Examples

Use [`hello-gateway`](examples/hello-gateway/) and [`rate-limit-basics`](examples/rate-limit-basics/) as models.

- One folder per example: `examples/<kebab-case-name>/`, containing:
  - `README.md`: the tutorial
  - `gateway.yaml`: the gateway config
  - `docker-compose.yml`: runs the gateway and the backend(s)
  - `app/`: the backend source and its `Dockerfile`
- The README follows this layout:
  1. A title and the line `### *Gateway Version used in this Tutorial vX.Y.Z-beta*`
  2. A "You will see" list of what the reader learns
  3. "Required tools"
  4. Numbered steps: the backend, the gateway config, a `nocleye check` step with its expected output, run it, try it, read the logs, clean up
  5. "Next steps" with links to the [docs](https://nocleye.com/docs/)
- Every file shown in the README must match the file on disk.
- Pin the gateway image tag (`nocleye/api-gateway:vX.Y.Z-beta`), never `latest`.
- Only the gateway publishes ports. Backends are reached through it.
- Backends can use any language or open source tool. Keep dependencies as few as possible.
- Never commit real secrets. Use values that are clearly fake.
- Add or update the example's row in [`examples/README.md`](examples/README.md) (name, date, gateway version).

## Lab

See [`lab/README.md`](lab/README.md) for how the lab works.

- Everything stays inside `lab/`. The lab must not use files from outside that folder.
- Config files are added through `configMapGenerator` in [`lab/kustomization.yaml`](lab/kustomization.yaml).
- Pin image and tool versions. `up.sh` must stay safe to re-run.
- If you change apps, ports or URLs, update the tables in `lab/README.md`. If you change dashboard panels, update the screenshot.
- Test on a fresh cluster before opening the pull request:

  ```sh
  lab/down.sh && lab/up.sh
  lab/traffic.sh
  # then check the dashboard at http://localhost:3500
  ```

## Moving to a new gateway version

1. Find every pinned version: `grep -rn "api-gateway:v" examples lab`
2. Bump the tags and the "Gateway Version used in this Tutorial" lines.
3. Run the example or the lab again and refresh the expected outputs in the READMEs.
4. Update the version and date in [`examples/README.md`](examples/README.md).

## Pull requests

- One topic per pull request.
- Short, imperative commit messages, for example `fix rate-limit-basics compose file`.
- Fill in the pull request template.

## License

This repository is under the [MIT license](LICENSE). By opening a pull request, you agree that your contribution is licensed under it.
