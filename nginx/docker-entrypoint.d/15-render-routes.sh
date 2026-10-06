#!/bin/sh
# Renders nginx/routes-templates/*.conf.template into /etc/nginx/routes/, substituting only the
# upstream URL variables. Kept separate from the image's own envsubst-on-templates.sh (which writes
# to conf.d, http context) because these files are location blocks: they must land in a directory
# the server block includes (routes/), not conf.d.
#
# Locally (Docker Compose) the defaults below point at the service names on the shared network,
# unchanged from before this template existed. In a host like Render, where a free service can only
# receive traffic on its public URL (not the private network), these are overridden with each
# service's public HTTPS URL.
set -eu

: "${AUTH_API_URL:=http://auth-api:8080}"
: "${CUSTOMERS_API_URL:=http://customers-api:8080}"
: "${PRODUCTS_API_URL:=http://products-api:8080}"
: "${SALES_API_URL:=http://sales-api:8080}"
: "${WORKFLOW_URL:=http://workflow:8080}"
export AUTH_API_URL CUSTOMERS_API_URL PRODUCTS_API_URL SALES_API_URL WORKFLOW_URL

for template in /etc/nginx/routes-templates/*.conf.template; do
    name="$(basename "$template" .template)"
    envsubst '${AUTH_API_URL} ${CUSTOMERS_API_URL} ${PRODUCTS_API_URL} ${SALES_API_URL} ${WORKFLOW_URL}' \
        < "$template" > "/etc/nginx/routes/$name"
done
