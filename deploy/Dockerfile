FROM nginx:1.29.8-alpine

# The default site listens on 80 and is not ours.
RUN rm -f /etc/nginx/conf.d/default.conf

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/conf.d/20-server.conf /etc/nginx/conf.d/
# Rendered by the image's entrypoint into conf.d, substituting only FRONT_ORIGIN.
COPY nginx/conf.d/10-security.conf.template /etc/nginx/templates/10-security.conf.template
COPY nginx/routes/ /etc/nginx/routes/
COPY nginx/routes-templates/ /etc/nginx/routes-templates/
COPY nginx/snippets/ /etc/nginx/snippets/
COPY nginx/docker-entrypoint.d/15-render-routes.sh /docker-entrypoint.d/15-render-routes.sh
RUN chmod +x /docker-entrypoint.d/15-render-routes.sh

ENV FRONT_ORIGIN=http://localhost:3000 \
    NGINX_ENVSUBST_FILTER=FRONT_ORIGIN

EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
  CMD wget -qO- http://127.0.0.1:8000/health || exit 1
