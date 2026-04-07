#!/bin/sh
# ---------------------------------------------------------------------------
# SNI Router — entrypoint
# Generates /usr/local/etc/haproxy/haproxy.cfg from environment variables,
# validates it, then hands off to haproxy.
#
# Environment variables
# ---------------------
#  SNI_LISTEN_PORT=443           Port to listen on for TLS/SNI routing (default: 443)
#  SNI_ROUTE_N=hostname:ip:port  TLS SNI routing rules, N = 1, 2, 3 …
#                                  Wildcard: *.example.com matches any subdomain
#  SNI_HEALTH_N=/path            Optional HTTPS health-check path for SNI_ROUTE_N
#                                  When set, HAProxy performs an HTTPS GET on this
#                                  path (TLS, no cert verification) instead of a
#                                  plain TCP connect check. The Host header is set
#                                  to the SNI hostname. Example: /health
#  SNI_DEFAULT=ip:port           Default backend when no SNI rule matches (REQUIRED)
#  SNI_DEFAULT_HEALTH=/path      Optional HTTPS health-check path for SNI_DEFAULT
#  TCP_ROUTE_N=lport:ip:dport    Plain TCP port-based routing rules, N = 1, 2, 3 …
#  TCP_HEALTH_N=/path            Optional HTTP(S) health-check path for TCP_ROUTE_N
#  SNI_ROUTES=<multiline>        Alternative to SNI_ROUTE_N: one hostname:ip:port per line.
#                                  Lines starting with # and blank lines are ignored.
#                                  Processed after SNI_ROUTE_N rules. Useful with Docker
#                                  Compose block-scalar YAML (|).
#  SNI_HEALTH_<norm>=<path>      HTTPS health-check path for an SNI_ROUTES entry.
#                                  <norm> is the hostname with ., *, - replaced by _.
#                                  Example: SNI_HEALTH_docs_example_com=/health
#  SNI_HTTP_REDIRECT=true        Create an HTTP frontend on SNI_HTTP_PORT (default: 80).
#                                  Unmatched requests are 301-redirected to HTTPS.
#                                  Enables Let's Encrypt http-01 challenge forwarding.
#  SNI_HTTP_PORT=80              Port for the HTTP frontend (default: 80)
#  HTTP_ROUTE_N=hostname:ip:p    HTTP routing rules for the HTTP frontend, N = 1, 2, 3 …
#  HTTP_ROUTES=<multiline>       Alternative to HTTP_ROUTE_N: one hostname:ip:port per line.
#  PROXY_PROTOCOL=true           Forward PROXY protocol v2 header to backends
#                                  so that upstream services see the real client IP
#  STATS_ENABLED=true            Enable HAProxy built-in stats web UI (default: false)
#  STATS_PORT=8404               Port for the stats UI (default: 8404)
#  STATS_PASSWORD=secret         Password for the stats UI — user is always "admin"
#                                  Leave empty to disable authentication
# ---------------------------------------------------------------------------
set -e

CFG=/usr/local/etc/haproxy/haproxy.cfg
LISTEN_PORT="${SNI_LISTEN_PORT:-443}"
PROXY_PROTO="${PROXY_PROTOCOL:-false}"
STATS_ENABLED="${STATS_ENABLED:-false}"
STATS_PORT="${STATS_PORT:-8404}"
STATS_PASSWORD="${STATS_PASSWORD:-}"

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
server_opts() {
  local opts="check inter 2s fall 3 rise 2"
  [ "$PROXY_PROTO" = "true" ] && opts="$opts send-proxy-v2"
  echo "$opts"
}

# --------------------------------------------------------------------------
# Mandatory: SNI_DEFAULT
# --------------------------------------------------------------------------
if [ -z "${SNI_DEFAULT:-}" ]; then
  echo "[sni-router] ERROR: SNI_DEFAULT is required. Example: SNI_DEFAULT=192.168.1.10:443" >&2
  exit 1
fi

SNI_DEFAULT_IP="$(echo "$SNI_DEFAULT"   | cut -d: -f1)"
SNI_DEFAULT_PORT="$(echo "$SNI_DEFAULT" | cut -d: -f2)"

# --------------------------------------------------------------------------
# Build use_backend ACL lines and backend blocks for SNI_ROUTE_N vars
# --------------------------------------------------------------------------
# Exact and wildcard ACL rules are kept in separate buckets so that exact
# matches are always emitted first in the frontend, regardless of the order
# routes are declared.  HAProxy uses first-match semantics, so without this
# a wildcard (*.example.com) defined before a specific rule
# (sub.example.com) would shadow the specific one.
SNI_ACL_EXACT=""
SNI_ACL_WILDCARD=""
SNI_BACKEND_BLOCKS=""
i=1

while true; do
  eval "val=\${SNI_ROUTE_${i}:-}"
  [ -z "$val" ] && break

  hostname="$(echo "$val" | cut -d: -f1)"
  ip="$(echo "$val"       | cut -d: -f2)"
  port="$(echo "$val"     | cut -d: -f3)"
  name="sni_backend_${i}"
  opts="$(server_opts)"

  if [ -z "$hostname" ] || [ -z "$ip" ] || [ -z "$port" ]; then
    echo "[sni-router] ERROR: SNI_ROUTE_${i}='${val}' must follow hostname:ip:port format." >&2
    exit 1
  fi

  # Wildcard: *.example.com  →  req.ssl_sni ends with .example.com
  case "$hostname" in
    \*.*)  
      suffix="${hostname#\*}"   # strip leading '*' → .example.com
      SNI_ACL_WILDCARD="${SNI_ACL_WILDCARD}
  use_backend ${name} if { req.ssl_sni -m end ${suffix} }"
      ;;
    *)
      SNI_ACL_EXACT="${SNI_ACL_EXACT}
  use_backend ${name} if { req.ssl_sni -i ${hostname} }"
      ;;
  esac
  if [ -n "$health_path" ]; then
    opts="${opts} ssl verify none"
    SNI_BACKEND_BLOCKS="${SNI_BACKEND_BLOCKS}
backend ${name}
  option httpchk
  http-check send meth GET uri ${health_path} ver HTTP/1.1 hdr Host ${hostname}
  server s1 ${ip}:${port} ${opts}
"
  else
    SNI_BACKEND_BLOCKS="${SNI_BACKEND_BLOCKS}
backend ${name}
  server s1 ${ip}:${port} ${opts}
"
  fi

  i=$((i + 1))
done

# --------------------------------------------------------------------------
# Build use_backend ACL lines and backend blocks for SNI_ROUTES multiline var
# --------------------------------------------------------------------------
if [ -n "${SNI_ROUTES:-}" ]; then
  while IFS= read -r line; do
    case "$line" in
      ''|\#*) continue ;;
    esac

    hostname="$(echo "$line" | cut -d: -f1)"
    ip="$(echo "$line"       | cut -d: -f2)"
    port="$(echo "$line"     | cut -d: -f3)"
    name="sni_backend_${i}"
    opts="$(server_opts)"

    if [ -z "$hostname" ] || [ -z "$ip" ] || [ -z "$port" ]; then
      echo "[sni-router] ERROR: SNI_ROUTES entry '${line}' must follow hostname:ip:port format." >&2
      exit 1
    fi

    case "$hostname" in
      \*.*)
        suffix="${hostname#\*}"
        SNI_ACL_WILDCARD="${SNI_ACL_WILDCARD}
  use_backend ${name} if { req.ssl_sni -m end ${suffix} }"
        ;;
      *)
        SNI_ACL_EXACT="${SNI_ACL_EXACT}
  use_backend ${name} if { req.ssl_sni -i ${hostname} }"
        ;;
    esac
    eval "health_path=\${SNI_HEALTH_${norm_name}:-}"
    if [ -n "$health_path" ]; then
      opts="${opts} ssl verify none"
      SNI_BACKEND_BLOCKS="${SNI_BACKEND_BLOCKS}
backend ${name}
  option httpchk
  http-check send meth GET uri ${health_path} ver HTTP/1.1 hdr Host ${hostname}
  server s1 ${ip}:${port} ${opts}
"
    else
      SNI_BACKEND_BLOCKS="${SNI_BACKEND_BLOCKS}
backend ${name}
  server s1 ${ip}:${port} ${opts}
"
    fi

    i=$((i + 1))
  done <<SNI_ROUTES_EOF
${SNI_ROUTES}
SNI_ROUTES_EOF
fi

# --------------------------------------------------------------------------
# Build frontend + backend blocks for TCP_ROUTE_N vars (plain TCP, no TLS)
# --------------------------------------------------------------------------
TCP_BLOCKS=""
j=1

while true; do
  eval "val=\${TCP_ROUTE_${j}:-}"
  [ -z "$val" ] && break

  lport="$(echo "$val" | cut -d: -f1)"
  ip="$(echo "$val"    | cut -d: -f2)"
  dport="$(echo "$val" | cut -d: -f3)"
  name="tcp_backend_${j}"
  opts="$(server_opts)"

  if [ -z "$lport" ] || [ -z "$ip" ] || [ -z "$dport" ]; then
    echo "[sni-router] ERROR: TCP_ROUTE_${j}='${val}' must follow listen_port:ip:dest_port format." >&2
    exit 1
  fi

  # Check for optional health-check path
  eval "health_path=\${TCP_HEALTH_${j}:-}"
  if [ -n "$health_path" ]; then
    opts="${opts} ssl verify none"
    TCP_BLOCKS="${TCP_BLOCKS}
frontend tcp_frontend_${j}
  bind *:${lport}
  default_backend ${name}

backend ${name}
  option httpchk
  http-check send meth GET uri ${health_path} ver HTTP/1.1 hdr Host localhost
  server s1 ${ip}:${dport} ${opts}
"
  else
    TCP_BLOCKS="${TCP_BLOCKS}
frontend tcp_frontend_${j}
  bind *:${lport}
  default_backend ${name}

backend ${name}
  server s1 ${ip}:${dport} ${opts}
"
  fi

  j=$((j + 1))
done

# --------------------------------------------------------------------------
# Build frontend + backend blocks for HTTP routing / Let's Encrypt http-01
# --------------------------------------------------------------------------
HTTP_ACL_LINES=""
HTTP_BACKEND_BLOCKS=""
HTTP_LISTEN_PORT="${SNI_HTTP_PORT:-80}"
k=1

while true; do
  eval "val=\${HTTP_ROUTE_${k}:-}"
  [ -z "$val" ] && break

  hostname="$(echo "$val" | cut -d: -f1)"
  ip="$(echo "$val"       | cut -d: -f2)"
  port="$(echo "$val"     | cut -d: -f3)"
  name="http_backend_${k}"

  if [ -z "$hostname" ] || [ -z "$ip" ] || [ -z "$port" ]; then
    echo "[sni-router] ERROR: HTTP_ROUTE_${k}='${val}' must follow hostname:ip:port format." >&2
    exit 1
  fi

  HTTP_ACL_LINES="${HTTP_ACL_LINES}
  use_backend ${name} if { hdr_dom(host) -i ${hostname} }"

  HTTP_BACKEND_BLOCKS="${HTTP_BACKEND_BLOCKS}
backend ${name}
  mode http
  server s1 ${ip}:${port} check inter 2s fall 3 rise 2
"
  k=$((k + 1))
done

if [ -n "${HTTP_ROUTES:-}" ]; then
  while IFS= read -r line; do
    case "$line" in
      ''|\#*) continue ;;
    esac

    hostname="$(echo "$line" | cut -d: -f1)"
    ip="$(echo "$line"       | cut -d: -f2)"
    port="$(echo "$line"     | cut -d: -f3)"
    name="http_backend_${k}"

    if [ -z "$hostname" ] || [ -z "$ip" ] || [ -z "$port" ]; then
      echo "[sni-router] ERROR: HTTP_ROUTES entry '${line}' must follow hostname:ip:port format." >&2
      exit 1
    fi

    HTTP_ACL_LINES="${HTTP_ACL_LINES}
  use_backend ${name} if { hdr_dom(host) -i ${hostname} }"

    HTTP_BACKEND_BLOCKS="${HTTP_BACKEND_BLOCKS}
backend ${name}
  mode http
  server s1 ${ip}:${port} check inter 2s fall 3 rise 2
"
    k=$((k + 1))
  done <<HTTP_ROUTES_EOF
${HTTP_ROUTES}
HTTP_ROUTES_EOF
fi

HTTP_BLOCK=""
if [ "${SNI_HTTP_REDIRECT:-false}" = "true" ] || [ -n "$HTTP_ACL_LINES" ]; then
  HTTP_BLOCK="$(printf '\nfrontend http_frontend\n  bind *:%s\n  mode http\n  option httplog\n  option forwardfor\n%s\n  redirect scheme https code 301\n%s' "${HTTP_LISTEN_PORT}" "${HTTP_ACL_LINES}" "${HTTP_BACKEND_BLOCKS}")"
fi

# --------------------------------------------------------------------------
# Build stats block (optional)
# --------------------------------------------------------------------------
STATS_BLOCK=""
if [ "$STATS_ENABLED" = "true" ]; then
  if [ -n "$STATS_PASSWORD" ]; then
    AUTH_LINE="  stats auth admin:${STATS_PASSWORD}"
  else
    AUTH_LINE=""
  fi
  STATS_BLOCK="$(printf '\nlisten stats\n  bind *:%s\n  mode http\n  stats enable\n  stats uri /stats\n  stats refresh 10s\n  stats show-legends\n  stats show-node\n  stats hide-version\n%s\n' "${STATS_PORT:-8404}" "${AUTH_LINE}")"
fi

# --------------------------------------------------------------------------
# Assemble and write haproxy.cfg
# --------------------------------------------------------------------------
DEFAULT_OPTS="$(server_opts)"

# Build default backend block (with optional HTTPS health check)
SNI_DEFAULT_HEALTH_PATH="${SNI_DEFAULT_HEALTH:-}"
if [ -n "$SNI_DEFAULT_HEALTH_PATH" ]; then
  DEFAULT_OPTS="${DEFAULT_OPTS} ssl verify none"
  DEFAULT_BACKEND_BLOCK="backend sni_default
  option httpchk
  http-check send meth GET uri ${SNI_DEFAULT_HEALTH_PATH} ver HTTP/1.1 hdr Host localhost
  server s1 ${SNI_DEFAULT_IP}:${SNI_DEFAULT_PORT} ${DEFAULT_OPTS}"
else
  DEFAULT_BACKEND_BLOCK="backend sni_default
  server s1 ${SNI_DEFAULT_IP}:${SNI_DEFAULT_PORT} ${DEFAULT_OPTS}"
fi

cat > "$CFG" <<HAPROXY_CFG
global
  log stdout format raw local0 info
  maxconn 50000

defaults
  mode tcp
  log global
  option tcplog
  timeout connect 5s
  timeout client 300s
  timeout server 300s
  option redispatch
  retry-on conn-failure empty-response response-timeout
  retries 3

frontend sni_tls
  bind *:${LISTEN_PORT}
  tcp-request inspect-delay 5s
  tcp-request content accept if { req.ssl_hello_type 1 }
${SNI_ACL_EXACT}
${SNI_ACL_WILDCARD}
  default_backend sni_default

${DEFAULT_BACKEND_BLOCK}
${SNI_BACKEND_BLOCKS}${TCP_BLOCKS}${HTTP_BLOCK}${STATS_BLOCK}
HAPROXY_CFG

# --------------------------------------------------------------------------
# Show generated config and validate before starting
# --------------------------------------------------------------------------
echo "[sni-router] ---- Generated ${CFG} ----"
cat "$CFG"
echo "[sni-router] ----------------------------------"

echo "[sni-router] Validating config..."
if ! haproxy -c -f "$CFG"; then
  echo "[sni-router] ERROR: Invalid config. Aborting." >&2
  exit 1
fi

echo "[sni-router] Config OK. Starting HAProxy..."
exec "$@"
