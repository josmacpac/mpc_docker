#!/usr/bin/env bash
# ==============================================================================
# mpc-docker / start.sh
# Levanta el entorno completo de MyPetCare en Docker.
#
# Uso:
#   ./scripts/start.sh              ← inicio normal
#   ./scripts/start.sh --build      ← reconstruir imágenes
#   ./scripts/start.sh --down       ← apagar todo
#   ./scripts/start.sh --logs       ← ver logs
#   ./scripts/start.sh --status     ← ver estado de contenedores
# ==============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE=".env"
COMPOSE="docker compose"

# ------------------------- Verificar .env -------------------------
if [ ! -f "$ENV_FILE" ]; then
  echo "No se encontró .env"
  echo ""
  if [ -f ".env.example" ]; then
    echo "¿Quieres copiar .env.example como .env?"
    read -r -p "(s/n) [s]: " resp || resp="s"
    resp="${resp:-s}"
    if [ "$resp" = "s" ] || [ "$resp" = "S" ]; then
      cp .env.example .env
      echo "✓ .env creado. Edita los valores antes de continuar."
      echo "  nano .env"
      exit 0
    else
      echo "Copia .env.example manualmente:  cp .env.example .env"
      exit 1
    fi
  else
    echo "No hay .env.example disponible."
    exit 1
  fi
fi

# ------------------------- Verificar repos hermanos -------------------------
check_repo() {
  local var_name="$1"
  local repo_name="$2"
  local path
  path=$(grep "^${var_name}=" "$ENV_FILE" | cut -d'=' -f2-)
  path="${path:-../$repo_name}"
  if [ ! -d "$path" ]; then
    echo "⚠  No se encontró: $path ($repo_name)"
    echo "   Ajusta ${var_name} en .env"
    return 1
  fi
  return 0
}

echo "Verificando repositorios..."
ok=true
check_repo "MPC_API_PATH" "mypetcare_api" || ok=false
check_repo "MPC_VET_PATH" "mpc_frontend" || ok=false
check_repo "MPC_ADMIN_PATH" "admin_mpc" || ok=false
check_repo "MPC_CLIENTES_PATH" "mpc_clientes" || ok=false

if [ "$ok" = false ]; then
  echo ""
  echo "Edita las rutas en .env y vuelve a ejecutar."
  exit 1
fi
echo "✓ Todos los repos encontrados"
echo ""

# ------------------------- Acciones -------------------------
case "${1:-}" in
  --down)
    echo "Apagando contenedores..."
    $COMPOSE down
    echo "✓ Contenedores apagados"
    exit 0
    ;;
  --logs)
    $COMPOSE logs -f
    exit 0
    ;;
  --status)
    $COMPOSE ps
    exit 0
    ;;
  --build)
    echo "Reconstruyendo imágenes..."
    $COMPOSE build --no-cache
    echo ""
    echo "Levantando entorno..."
    $COMPOSE up -d
    echo ""
    echo "✓ Entorno levantado con rebuild"
    echo "  → http://localhost/vet/"
    echo "  → http://localhost/admin/"
    echo "  → http://localhost/clientes/"
    echo "  → http://localhost/api/"
    echo ""
    echo "Ver logs:  ./scripts/start.sh --logs"
    exit 0
    ;;
  --help|-h)
    echo "Uso: ./scripts/start.sh [opciones]"
    echo ""
    echo "Opciones:"
    echo "  (sin args)    Iniciar entorno (build si es la primera vez)"
    echo "  --build       Reconstruir imágenes desde cero"
    echo "  --down        Apagar todos los contenedores"
    echo "  --logs        Ver logs en tiempo real"
    echo "  --status      Ver estado de contenedores"
    echo "  --help        Mostrar esta ayuda"
    exit 0
    ;;
esac

# ------------------------- Inicio normal -------------------------
echo "=============================================="
echo "  mpc-docker — MyPetCare Local"
echo "=============================================="
echo ""

# Verificar si las imágenes ya están construidas
if $COMPOSE images -q 2>/dev/null | grep -q .; then
  echo "Imágenes existentes detectadas."
  echo ""
  echo "¿Qué hacer?"
  echo "  1) Usar imágenes existentes (rápido)"
  echo "  2) Reconstruir todo (lento, pero actualizado)"
  read -r -p "Elige (1-2) [1]: " choice || choice=""
  choice="${choice:-1}"

  if [ "$choice" = "2" ]; then
    echo ""
    echo "Reconstruyendo..."
    $COMPOSE build --no-cache
  fi
else
  echo "Primera ejecución: construyendo imágenes..."
  $COMPOSE build
fi

echo ""
echo "Levantando servicios..."
$COMPOSE up -d

echo ""
echo "=============================================="
echo "  ✓ Entorno listo!"
echo ""
echo "  → Vet:      http://localhost/vet/"
echo "  → Admin:    http://localhost/admin/"
echo "  → Clientes: http://localhost/clientes/"
echo "  → API:      http://localhost/api/"
echo ""
echo "  Ver logs:   ./scripts/start.sh --logs"
echo "  Apagar:     ./scripts/start.sh --down"
echo "=============================================="
