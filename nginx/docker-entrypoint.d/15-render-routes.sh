#!/bin/sh
# Renders nginx/routes-templates/*.conf.template, substituting only the variables it declares.
# Kept separate from the image's own envsubst-on-templates.sh (which only handles FRONT_ORIGIN,
# writing to conf.d) because these files need two different destinations:
#   - 00-resolver.conf.template -> /etc/nginx/conf.d/ (http context: a bare `resolver` directive)
#   - every other *.conf.template -> /etc/nginx/routes/ (server context: location blocks, included
#     by 20-server.conf's `include /etc/nginx/routes/*.conf;`)
#
# Locally (Docker Compose) the defaults below reproduce the exact previous hardcoded behavior
# (Docker's embedded DNS, Compose service names). On a host like Render, where upstreams are each
# service's public HTTPS URL instead and Docker's DNS does not exist, these are overridden.
set -eu

: "${NGINX_RESOLVER:=127.0.0.11}"
: "${AUTH_API_URL:=http://auth-api:8080}"
: "${CUSTOMERS_API_URL:=http://customers-api:8080}"
: "${PRODUCTS_API_URL:=http://products-api:8080}"
: "${SALES_API_URL:=http://sales-api:8080}"
: "${WORKFLOW_URL:=http://workflow:8080}"
export NGINX_RESOLVER AUTH_API_URL CUSTOMERS_API_URL PRODUCTS_API_URL SALES_API_URL WORKFLOW_URL

envsubst '${NGINX_RESOLVER}' \
    < /etc/nginx/routes-templates/00-resolver.conf.template > /etc/nginx/conf.d/00-resolver.conf

for template in /etc/nginx/routes-templates/*.conf.template; do
    name="$(basename "$template" .template)"
    [ "$name" = "00-resolver.conf" ] && continue
    envsubst '${AUTH_API_URL} ${CUSTOMERS_API_URL} ${PRODUCTS_API_URL} ${SALES_API_URL} ${WORKFLOW_URL}' \
        < "$template" > "/etc/nginx/routes/$name"
done
