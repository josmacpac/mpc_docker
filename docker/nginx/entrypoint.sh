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

  if [ ! -f "$app_dir/scripts/inject-env.js" ]; then
    echo "  ⚠ $name: inject-env.js no encontrado, saltando"
    return
  fi

  echo "  → $name: inyectando config.js..."

  API_URL="$api_url_var" \
  SUPABASE_URL="$supabase_url_var" \
  SUPABASE_ANON_KEY="$anon_key_var" \
  node "$app_dir/scripts/inject-env.js"
}

echo ""
echo "1/3 Inyectando configuración de frontends..."

inject_config "Vet" "/app/vet" \
  "$VET_API_URL" "$VET_SUPABASE_URL" "$VET_SUPABASE_ANON_KEY"

inject_config "Admin" "/app/admin" \
  "$ADMIN_API_URL" "$ADMIN_SUPABASE_URL" "$ADMIN_SUPABASE_ANON_KEY"

# -------------------------------------------------------------------
# 2. Build de clientes (Vite) si no existe dist/
# -------------------------------------------------------------------
echo ""
echo "2/3 Verificando build de clientes..."

if [ -d "/app/clientes/dist" ] && [ -f "/app/clientes/dist/index.html" ]; then
  echo "  → Clientes: dist/ ya existe, saltando build"
else
  echo "  → Clientes: ejecutando vite build..."
  cd /app/clientes
  if [ ! -d "node_modules" ]; then
    echo "  → Clientes: npm install..."
    npm install --silent
  fi
  VITE_API_URL="$CLIENTES_API_URL" npm run build
  cd /
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
echo "  → API:      http://localhost/api/"
echo "=============================================="
echo ""

# Ejecutar el comando principal (nginx)
exec "$@"
