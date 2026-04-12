---
seo:
  title: SNI Router — TLS/SNI passthrough router
  description: TLS/SNI passthrough router built on HAProxy — route HTTPS traffic by hostname without decrypting.
---

:::u-page-hero
#title
Route TLS traffic by hostname — without decrypting.

#description
SNI Router is a lightweight, HAProxy-based TLS/SNI passthrough router. It reads the SNI hostname from the TLS ClientHello and forwards the raw TCP stream to the matching backend — **zero decryption, zero certificate management**. Configured entirely via environment variables.

#links
::::u-button{to="/docs/getting-started/introduction" size="xl" trailing-icon="i-lucide-arrow-right" color="neutral"}
Get Started
::::

::::u-button{to="https://github.com/circle-rd/sni-router" target="_blank" size="xl" variant="outline" color="neutral" icon="i-simple-icons-github"}
Star on GitHub
::::
:::

:::u-page-section
#title
Why SNI Router?

#features
::::u-page-feature{icon="i-lucide-lock" title="TLS passthrough" description="Reads only the TLS ClientHello SNI field. The byte stream is forwarded untouched — backends manage their own certificates."}
::::
::::u-page-feature{icon="i-lucide-network" title="Multi-backend routing" description="Route traffic from a single public IP to multiple backends by hostname. Wildcard rules (*.example.com) are supported."}
::::
::::u-page-feature{icon="i-lucide-settings-2" title="Environment-only config" description="No config file to maintain. All routes and options are set via environment variables or a Docker Compose block scalar."}
::::
::::u-page-feature{icon="i-lucide-shield-check" title="Automatic priority sorting" description="Exact hostnames always win over wildcards, regardless of declaration order. The HAProxy config is generated and validated at startup."}
::::
::::u-page-feature{icon="i-lucide-cable" title="TCP + HTTP routing" description="Route plain TCP connections by listen port and HTTP traffic with optional Let's Encrypt http-01 challenge forwarding."}
::::
::::u-page-feature{icon="i-lucide-radio" title="PROXY protocol v2" description="Optionally prepend PROXY protocol v2 headers so backends recover the real client IP instead of the router address."}
::::
:::
