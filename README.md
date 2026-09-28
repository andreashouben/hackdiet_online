# The Hacker's Diet Online, in a container

[The Hacker's Diet Online](https://www.fourmilab.ch/hackdiet/online/hdo.html)
is the web-based weight tracker John Walker built to accompany his book
[The Hacker's Diet](https://www.fourmilab.ch/hackdiet/). You log your weight
every day, and it computes the moving-average trend, draws charts, runs trend
analyses and helps you plan a diet.

This repository packages Walker's original Perl CGI code (version 1.0, 2007)
as a Docker image, so you can run your own instance, for example on a home
server.

## Running it

You need Docker with Compose. Copy [`compose.yaml`](compose.yaml) to your
server and start it:

```sh
docker compose up -d
```

Then open `http://<server>:8080` and create an account. Anyone who can
reach the port can sign up, so once your account exists, set
`HDIET_REGISTRATION=closed` and run `docker compose up -d` again.

Configuration is optional. Either edit `compose.yaml` directly, or put a
`.env` file next to it (see [`.env.example`](.env.example)):

| Variable | Default | Purpose |
|---|---|---|
| `HDIET_PORT` | `8080` | Host port the app is published on |
| `HDIET_REGISTRATION` | `open` | `closed` refuses new accounts |
| `HDIET_BASE_URL` | from request | Public address, e.g. `https://hackdiet.example.org`, used in the badge embed code, e-mails and XML exports. Without it the address is taken from the `Host` and `X-Forwarded-Proto` headers, which works behind a reverse proxy that passes them on. Setting it is safer, since a client controls the `Host` header. |
| `HDIET_BADGE_KEY` | generated | Key used to encrypt the user ID in badge image URLs. Changing it breaks badge URLs that were already embedded. |
| `HDIET_SALT` | generated | Salt for "remember me" cookie signatures and the confirmation codes of destructive actions. Changing it signs out remembered sessions. |

If `HDIET_BADGE_KEY` or `HDIET_SALT` is not set, the container generates a
random value on first start and keeps it in the data volume under
`.secrets/`, so it survives updates. Only set them if you want to manage the
secrets yourself (`openssl rand -hex 32`).

The container only speaks plain HTTP. If the server is reachable from
anywhere but your own network, put a reverse proxy with TLS in front
(Caddy, Traefik, nginx); otherwise passwords and session IDs travel
unencrypted.

To update:

```sh
docker compose pull && docker compose up -d
```

### Data and backups

All user data is stored as plain files in the volume `hackdiet-data`
(mounted at `/server/pub/hackdiet`), together with the generated secrets.
To back it up:

```sh
docker run --rm -v hackdiet-data:/data -v "$PWD":/backup busybox \
    tar czf /backup/hackdiet-backup.tgz -C /data .
```

Compose prefixes volume names with the project name (usually the directory
name), so the volume may be called e.g. `hackdiet_hackdiet-data`. Check with
`docker volume ls`.

Each user can also export and import their weight log as CSV or XML from
the account page.

## Development

```sh
docker compose up -d --build     # builds from this checkout (compose.override.yaml)
scripts/smoke-test.sh            # end-to-end test against http://localhost:8080
```

The smoke test creates a throwaway account named `smoke…` in the database.
With `EXPECT_REGISTRATION=closed` it only checks that sign-up is refused.

CI builds the image, runs the smoke test and, on pushes to `main` and `v*`
tags, publishes a multi-arch image (amd64, arm64) to
`ghcr.io/andreashouben/hackdiet_online`.

### How the container is put together

The Perl code has absolute paths baked in, so instead of patching them the
image reproduces the original server layout:

| Path | Content |
|---|---|
| `/server/bin/httpd/cgi-bin` | `HackDiet`, `HackDietBadge` and the `HDiet/` modules |
| `/server/web/hackdiet/online` | static files, served at `/hackdiet/online` |
| `/server/pub/hackdiet` | user database (volume) |

Apache runs the two CGI programs ([`docker/hackdiet.conf`](docker/hackdiet.conf)).
The entrypoint creates the database directories and starts a small syslog
daemon, because the app logs failed sign-ins to syslog.

### Source code and nuweb

Walker wrote the program as a literate program: [`hdiet.w`](hdiet.w) is a
single [nuweb](https://nuweb.sourceforge.net/) document that contains both
the documentation ([`hdiet.pdf`](hdiet.pdf)) and the code. All `.pl`, `.pm`,
`.js`, `.css` and `.html` files in this repository were generated from it.

In this repository the generated files are the source; changes are made
directly to them. `hdiet.w` is kept as the original, but it is **no longer in
sync** with the code, and regenerating from it would undo the changes below.
`hdiet.pdf` is still the best documentation of how the program works.

### Changes from the original

The first commit in this repository is Walker's code as published (minus
`Times.ttf`, see below); `git diff` against it shows every change. In short:

- The badge encryption key and the salt are read from `HDIET_BADGE_KEY`
  and `HDIET_SALT` instead of being compiled in
  (`HDiet/user.pm`, `HackDietBadge.pl`, `HDiet/cookie.pm`, `HackDiet.pl`).
- The "remember me" cookie no longer carries `Domain=.fourmilab.ch`,
  which made browsers reject it on any other host (`HDiet/cookie.pm`).
- New accounts can be disabled with `HDIET_REGISTRATION=closed`
  (`HackDiet.pl`).
- The XML import no longer fetches the DTD referenced in the DOCTYPE of
  exported files; the request to fourmilab.ch failed and aborted the
  import (`HackDiet.pl`).
- Addresses of this installation no longer point to fourmilab.ch: the
  badge embed code, the password reset e-mail and the stylesheet and DTD
  references in XML exports use `HDIET_BASE_URL` or the request's host
  (`HDiet/html.pm`, `HDiet/xml.pm`, `HackDiet.pl`), and the HTTP warning
  on the sign-in page suggests the HTTPS address of this server
  (`hdiet.js`). Links that are explicitly meant for fourmilab.ch, such as
  the logos and the documentation link, are unchanged.
- `HDiet/Fonts/Times.ttf` (Times New Roman, not redistributable) is not
  included; the image uses the metric-compatible Liberation Serif instead.
- The images under `figures/` were missing from the source distribution
  and were taken from fourmilab.ch (see [THIRD_PARTY.md](THIRD_PARTY.md)).

Clustering (`HDiet/Cluster.pm`, `ClusterSync.pl`) still uses the original
salt, but it is inactive because no cluster hosts are configured.

## Known limitations

- **HTTPS warning.** The sign-in page warns when it is not served over
  HTTPS (except on localhost). A reverse proxy with TLS makes it go away.
- **No e-mail.** There is no `sendmail` in the image, so password reset and
  the feedback form do not work. The sender and feedback addresses in the
  code are still the original fourmilab.ch ones.

## License

John Walker dedicated The Hacker's Diet Online to the public domain. The
packaging in this repository (Docker, Compose, CI, scripts, documentation) is
released under [CC0 1.0](LICENSE), which is public domain where the law
allows it and an unconditional license everywhere else.

A few bundled files are by other authors and keep their own licenses; see
[THIRD_PARTY.md](THIRD_PARTY.md).
