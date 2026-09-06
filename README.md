# MPC Docker

Entorno local completo de **MyPetCare** usando Docker Compose. Levanta la API, los 3 frontends y un reverse proxy con un solo comando.

## Arquitectura

```
localhost:80
    │
    ├── /vet/       → Panel Veterinario (HTML/JS estático)
    ├── /admin/     → Panel Administración (HTML/JS estático)
    ├── /clientes/  → Portal Clientes (Vue 3 + Vite)
    └── /api/*      → Proxy → Flask API (Python 3.12 + gunicorn)
                              └── Supabase (PostgreSQL + Auth)
```

| Servicio | Puerto | Tecnología |
|----------|--------|------------|
| api | 5000 (interno) | Python 3.12, Flask, gunicorn |
| nginx | 80 (expuesto) | Nginx, Node.js 20 |

## Requisitos

- [Docker](https://docs.docker.com/get-docker/) >= 24.x
- [Docker Compose](https://docs.docker.com/compose/install/) >= 2.x
- Los 4 repos clonados como hermanos:

```
Desarrollo/
├── mpc_docker/         ← este repo
├── mypetcare_api/
├── mpc_frontend/
├── admin_mpc/
└── mpc_clientes/
```

## Instalación rápida

```bash
# 1. Clonar este repo
git clone https://github.com/josmacpac/mpc_docker.git
cd mpc_docker

# 2. Crear .env desde la plantilla
cp .env.example .env

# 3. Editar variables (Supabase, rutas, etc.)
nano .env

# 4. Levantar todo
./scripts/start.sh
```

## Variables de entorno (.env)

### Rutas a los repos

Las rutas son relativas a `mpc_docker/`. Si tus repos están en otro lugar, ajústalas:

```bash
MPC_API_PATH=../mypetcare_api
MPC_VET_PATH=../mpc_frontend
MPC_ADMIN_PATH=../admin_mpc
MPC_CLIENTES_PATH=../mpc_clientes
```

### API (Supabase)

```bash
SUPABASE_URL=https://tu-proyecto.supabase.co
SUPABASE_SERVICE_KEY=tu_service_key
SUPABASE_SERVICE_ROLE_KEY=tu_service_role_key
CORS_ORIGINS=http://localhost
```

### Frontends (inyección de config)

Cada frontend necesita la URL del API y las credenciales de Supabase. El entrypoint de Nginx ejecuta `inject-env.js` automáticamente al iniciar:

```bash
VET_API_URL=http://localhost/api
VET_SUPABASE_URL=https://tu-proyecto.supabase.co
VET_SUPABASE_ANON_KEY=tu_anon_key

ADMIN_API_URL=http://localhost/api
ADMIN_SUPABASE_URL=https://tu-proyecto.supabase.co
ADMIN_SUPABASE_ANON_KEY=tu_anon_key

CLIENTES_API_URL=http://localhost/api
```

## Comandos

| Comando | Descripción |
|---------|-------------|
| `./scripts/start.sh` | Inicio normal (pregunta si rebuild) |
| `./scripts/start.sh --build` | Reconstruir imágenes desde cero |
| `./scripts/start.sh --down` | Apagar todos los contenedores |
| `./scripts/start.sh --logs` | Ver logs en tiempo real |
| `./scripts/start.sh --status` | Ver estado de contenedores |

### Docker Compose directo

```bash
docker compose up -d              # levantar
docker compose down               # apagar
docker compose logs -f nginx      # logs de un servicio
docker compose build --no-cache   # rebuild completo
docker compose ps                 # estado
```

## URLs de acceso

| Servicio | URL |
|----------|-----|
| Panel Veterinario | http://localhost/vet/ |
| Panel Administración | http://localhost/admin/ |
| Portal Clientes | http://localhost/clientes/ |
| API (proxy) | http://localhost/api/ |
| API (directa) | http://localhost:5000/api/ |
| Healthcheck API | http://localhost:5000/api/health |

## Cómo funciona el entrypoint

Al levantar el contenedor de Nginx, `entrypoint.sh` ejecuta:

1. **Inyección de config** — Ejecuta `inject-env.js` en vet y admin con las variables de entorno para generar `js/config.js`
2. **Build de clientes** — Ejecuta `vite build` en mpc_clientes si no existe `dist/`
3. **Copia de archivos** — Copia los archivos estáticos a los directorios de Nginx
4. **Inicio de Nginx** — Arranca el servidor web con el proxy inverso

## Consideraciones

- **Supabase es externo** — No se ejecuta en Docker. La API se conecta directamente a tu proyecto en la nube.
- **Cold starts** — La primera vez que accedes a `/api/`, la API puede tardar ~30s si el contenedor recién inició.
- **Archivos estáticos** — vet y admin se sirven directo (sin build). Los cambios en código fuente requieren `--build` para reflejarse.
- **clientes** — Se construye con Vite dentro del contenedor. La primera ejecución puede tardar 1-2 minutos.
- **CORS** — El proxy de Nginx maneja todo como same-origin. No hay problemas de CORS en local.
- **Puerto 80** — Si tu máquina ya usa el puerto 80, cambia el mapeo en `docker-compose.yml`: `"8080:80"`.

## Próximos pasos: Pipeline CI/CD

### Fase 1: Testing automatizado

```
push a main / PR
  │
  ├── 1. docker compose build
  ├── 2. docker compose up -d
  ├── 3. Esperar healthcheck de la API
  ├── 4. Ejecutar mpc_tests (Playwright + Newman) contra localhost
  │     ├── npm run test:dev:vet
  │     ├── npm run test:dev:admin
  │     ├── npm run test:dev:clientes
  │     └── Newman API tests
  ├── 5. Si falla → notificar (Slack/Discord/email)
  └── 6. Si pass → continuar a deploy
```

### Fase 2: Deploy automático

```
merge a main (después de PR aprobado)
  │
  ├── API → push a mypetcare_api → Render hace deploy automático
  ├── Vet/Admin → push a sus repos → Netlify hace deploy automático
  └── Clientes → push a mpc_clientes → Netlify hace deploy automático
```

### Fase 3: Monitoreo post-deploy

```
deploy completado
  │
  ├── Verificar healthcheck de producción (admin_mpc monitoreo)
  ├── Verificar CORS origins en Render
  └── Notificar estado
```

### Stack sugerido para el pipeline

| Herramienta | Uso |
|-------------|-----|
| GitHub Actions | Orquestación del pipeline |
| Docker Compose | Levantar entorno de testing |
| Playwright | Tests E2E de frontends |
| Newman | Tests de API (Postman collections) |
| Supabase CLI | Migraciones de base de datos |

### Variables secrets para el pipeline

```yaml
# GitHub Actions secrets
SUPABASE_URL
SUPABASE_SERVICE_KEY
SUPABASE_SERVICE_ROLE_KEY
VET_SUPABASE_ANON_KEY
ADMIN_SUPABASE_ANON_KEY
```

### Ejemplo de workflow (GitHub Actions)

```yaml
name: CI/CD Pipeline
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Docker Compose
        run: cp .env.example .env

      - name: Configure environment
        run: |
          sed -i "s|SUPABASE_URL=.*|SUPABASE_URL=${{ secrets.SUPABASE_URL }}|" .env
          sed -i "s|SUPABASE_SERVICE_KEY=.*|SUPABASE_SERVICE_KEY=${{ secrets.SUPABASE_SERVICE_KEY }}|" .env
          # ... más variables

      - name: Build containers
        run: docker compose build

      - name: Start services
        run: docker compose up -d

      - name: Wait for API
        run: |
          for i in $(seq 1 30); do
            curl -sf http://localhost/api/health && break
            sleep 2
          done

      - name: Run API tests
        run: |
          cd ../mpc_tests
          bash -c 'set -a; source ../mpc_docker/.env; set +a; npx newman run ...'

      - name: Run E2E tests
        run: |
          cd ../mpc_tests
          bash -c 'set -a; source ../mpc_docker/.env; set +a; npx playwright test'

      - name: Stop services
        if: always()
        run: docker compose down
```

## Solución de problemas

### El puerto 80 ya está en uso

Cambia el mapeo en `docker-compose.yml`:
```yaml
ports:
  - "8080:80"
```

### Error "Cannot find module" en inject-env.js

Asegúrate de que Node.js está disponible en el contenedor. El Dockerfile de Nginx incluye Node.js 20.

### La API no responde

```bash
docker compose logs api       # ver errores
docker compose ps             # verificar estado
curl http://localhost:5000/api/health  # probar directo
```

### Los frontends muestran "config no disponible"

Las variables de Supabase no están configuradas en `.env`. Verifica `VET_SUPABASE_URL`, `VET_SUPABASE_ANON_KEY`, etc.

### Clientes no hace build

```bash
docker compose exec nginx sh   # entrar al contenedor
cd /app/clientes
npm install
VITE_API_URL=http://localhost/api npm run build
```

## Licencia

Proyecto privado — Y3N Software y Soluciones Digitales.
