## Historia de usuario
<!-- Referencia a la historia en el repositorio de documentacion: code-corhuila/opti-docs#NN -->

## Que cambia y por que


## Como se probo
<!-- Resultado de `nginx -t`, de `tests/smoke.sh` y del flujo ci.yml -->

## Rastro de promocion
<!-- Solo hacia qa o main: commits re-aplicados, cada uno con su linea "(cherry picked from commit <sha>)" -->

## Lista de verificacion
- [ ] Sin secretos ni credenciales en el cambio
- [ ] Una ruta nueva usa variable en `proxy_pass` (resolucion por peticion)
- [ ] El gateway sigue filtrando credencial pero no la valida
