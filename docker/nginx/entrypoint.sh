#!/bin/sh
set -e

echo "=============================================="
echo "  mpc-docker — Iniciando entorno"
echo "=============================================="

# -------------------------------------------------------------------
# 1. Inyectar config.js en vet y admin (inject-env.js)
# -------------------------------------------------------------------
inject_config() {
  local name="$1"
  local app_dir="$2"
  local api_url_var="$3"
  local supabase_url_var="$4"
  local anon_key_var="$5"
  local deploy_key_var="${6:-}"

  if [ ! -f "$app_dir/scripts/inject-env.js" ]; then
    echo "  ⚠ $name: inject-env.js no encontrado, saltando"
    return
  fi

  echo "  → $name: inyectando config.js..."

  API_URL="$api_url_var" \
  SUPABASE_URL="$supabase_url_var" \
  SUPABASE_ANON_KEY="$anon_key_var" \
  DEPLOY_KEY="$deploy_key_var" \
  node "$app_dir/scripts/inject-env.js"

  # El contenedor corre como root: si config.js quedó root-owned en el
  # host no se puede editar después. Hereda el dueño del directorio js/.
  if [ -f "$app_dir/js/config.js" ] && [ -d "$app_dir/js" ]; then
    chown --reference="$app_dir/js" "$app_dir/js/config.js" 2>/dev/null || true
  fi
}

echo ""
echo "1/3 Inyectando configuración de frontends..."

inject_config "Vet" "/app/vet" \
  "$VET_API_URL" "$VET_SUPABASE_URL" "$VET_SUPABASE_ANON_KEY"

inject_config "Admin" "/app/admin" \
  "$ADMIN_API_URL" "$ADMIN_SUPABASE_URL" "$ADMIN_SUPABASE_ANON_KEY" \
  "$DEPLOY_KEY"

# -------------------------------------------------------------------
# 2. Build de clientes (Vite) si no existe dist/
# -------------------------------------------------------------------
echo ""
echo "2/3 Verificando build de clientes..."

if [ -d "/app/clientes/dist" ] && [ -f "/app/clientes/dist/index.html" ]; then
  echo "  → Clientes: dist/ ya existe, saltando build"
else
  echo "  → Clientes: ejecutando vite build..."
  # Build no fatal: un error aquí no debe impedir arrancar el resto del entorno.
  if (
    cd /app/clientes
    if [ ! -d "node_modules" ]; then
      echo "  → Clientes: npm install..."
      npm install --silent
    fi
    VITE_API_URL="$CLIENTES_API_URL" npm run build
  ); then
    echo "  → Clientes: build OK"
  else
    echo "  ⚠ Clientes: build FALLÓ (ver arriba); se servirá dist/ existente o placeholder"
  fi
fi

# -------------------------------------------------------------------
# 2b. Build de app-clientes (nuevo portal B2C) — siempre fresco
# -------------------------------------------------------------------
echo ""
echo "2b/3 Build de app-clientes (nuevo portal)..."

if [ -f "/app/app-clientes/package.json" ]; then
  # node_modules es un volumen aislado (musl/Alpine) y NO comparte el del host
  # (glibc): hay que instalarlo cuando falten bindings musl o cuando el
  # package-lock.json del host sea más nuevo que lo instalado (paquete nuevo).
  need_install=0
  if [ ! -d "/app/app-clientes/node_modules" ]; then
    need_install=1
  else
    [ ! -d "/app/app-clientes/node_modules/@rolldown/binding-linux-x64-musl" ] && need_install=1
    if [ -d "/app/app-clientes/node_modules/lightningcss-linux-x64-gnu" ] \
       && [ ! -d "/app/app-clientes/node_modules/lightningcss-linux-x64-musl" ]; then
      need_install=1
    fi
    if [ -f "/app/app-clientes/package-lock.json" ]; then
      if [ ! -f "/app/app-clientes/node_modules/.package-lock.json" ] \
         || [ "/app/app-clientes/package-lock.json" -nt "/app/app-clientes/node_modules/.package-lock.json" ]; then
        echo "  → App Clientes: package-lock.json más nuevo que node_modules instalado..."
        need_install=1
      fi
    fi
  fi
  if [ "$need_install" = "1" ]; then
    echo "  → App Clientes: instalando dependencias (bindings musl + paquetes nuevos)..."
    if ! (cd /app/app-clientes && npm install --silent); then
      echo "  ⚠ App Clientes: npm install falló"
    fi
  fi

  # Build no fatal: si falla, se sirve el dist/ anterior si existe.
  if (
    cd /app/app-clientes
    if [ ! -d "node_modules" ]; then
      echo "  → App Clientes: npm install..."
      npm install --silent
    fi
    # VITE_API_URL vacío => same-origin (/api/ vía proxy de este nginx),
    # como en producción. --base=/app-clientes/ para el router y los assets.
    VITE_API_URL="${APP_CLIENTES_API_URL-}" npm run build -- --base=/app-clientes/
  ); then
    echo "  → App Clientes: build OK"
  else
    echo "  ⚠ App Clientes: build FALLÓ (ver arriba)"
  fi

  if [ -f "/app/app-clientes/dist/index.html" ]; then
    mkdir -p /usr/share/nginx/html/app-clientes
    cp -r /app/app-clientes/dist/. /usr/share/nginx/html/app-clientes/
    # El build corre como root dentro del contenedor: devuelve la propiedad
    # al usuario anfitrión para no romper builds posteriores en el host.
    owner=$(stat -c %u:%g /app/app-clientes 2>/dev/null || true)
    if [ -n "$owner" ]; then
      chown -R "$owner" /app/app-clientes/dist /app/app-clientes/node_modules/.vite 2>/dev/null || true
    fi
    echo "  → App Clientes: dist copiado"
  else
    echo "  ⚠ App Clientes: dist/ no disponible"
  fi
else
  echo "  ⚠ App Clientes: no montado en /app/app-clientes, saltando"
fi

# -------------------------------------------------------------------
# 3. Copiar archivos estáticos a directorios de Nginx
# -------------------------------------------------------------------
echo ""
echo "3/3 Copiando archivos a Nginx..."

# Vet: copiar todo el directorio (ya tiene config.js generado)
cp -r /app/vet/. /usr/share/nginx/html/vet/
echo "  → Vet: archivos copiados"

# Admin: copiar todo el directorio (ya tiene config.js generado)
cp -r /app/admin/. /usr/share/nginx/html/admin/
echo "  → Admin: archivos copiados"

# Clientes: copiar dist/
if [ -d "/app/clientes/dist" ]; then
  cp -r /app/clientes/dist/. /usr/share/nginx/html/clientes/
  echo "  → Clientes: dist/ copiado"
else
  echo "  → Clientes: dist/ no existe, creando placeholder"
  mkdir -p /usr/share/nginx/html/clientes
  echo "<h1>Clientes: build no disponible</h1>" > /usr/share/nginx/html/clientes/index.html
fi

echo ""
echo "=============================================="
echo "  Entorno listo!"
echo "  → Vet:      http://localhost/vet/"
echo "  → Admin:    http://localhost/admin/"
echo "  → Clientes: http://localhost/clientes/"
echo "  → App:      http://localhost/app-clientes/"
echo "  → API:      http://localhost/api/"
echo "=============================================="
echo ""

# Ejecutar el comando principal (nginx)
exec "$@"
