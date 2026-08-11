# SeguridadPro DNS v5.1

Módulo encapsulado para administrar dominios y subdominios por empresa.

## Primera versión funcional

- Panel exclusivo para `superadmin` en `/dominios`.
- Dominios propios, subdominios propios y subdominios del sistema.
- Un dominio principal por empresa.
- Verificación de registros A, AAAA o CNAME contra `PUBLIC_IP` o un destino indicado.
- Verificación de propiedad mediante TXT en `_seguridadpro-verification.<dominio>`.
- Estados Pendiente, Verificando, Activo, Error DNS, Error SSL y Suspendido.
- API pública `GET /api/public/domain/resolve?host=<dominio>`.
- Rechazo de dominios duplicados y empresas suspendidas o vencidas.

## Configuración

En el backend puede definirse la dirección esperada:

```env
PUBLIC_IP=203.0.113.20
```

La emisión dinámica de certificados y la automatización con Cloudflare quedan como
integraciones posteriores. Esta primera versión registra, verifica y resuelve la
empresa propietaria del dominio sin modificar la carpeta v5.0.
