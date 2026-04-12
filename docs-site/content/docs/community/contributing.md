---
title: Contributing
description: How to contribute to SNI Router.
---

# Contributing

Contributions are welcome. Please open issues and pull requests on the [SNI Router GitHub repository](https://github.com/circle-rd/sni-router).

## What to contribute

- Bug reports — open an issue with reproduction steps and the output of `docker compose logs sni-router`
- Feature requests — open an issue describing the use case
- Pull requests — shell script improvements, new environment variable options, documentation fixes

## Development setup

SNI Router has no build dependencies beyond Docker. To test changes locally:

```bash
git clone https://github.com/circle-rd/sni-router.git
cd sni-router

# Build the image locally
docker build -t sni-router:dev .

# Run with a test configuration
docker run --rm \
  -e SNI_ROUTE_1="app.example.com:127.0.0.1:443" \
  -e SNI_DEFAULT="127.0.0.1:443" \
  sni-router:dev haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

The last command runs the startup script and validates the generated config without starting HAProxy.

## Code style

The entrypoint is written in **POSIX sh** (`#!/bin/sh`). Avoid bashisms — the script must run in BusyBox `sh` (Alpine).

## Reporting security issues

Please do not open public issues for security vulnerabilities. Contact the maintainers directly via the GitHub repository security advisories feature.
