FROM node:20-alpine AS build

WORKDIR /app

# Copiar scripts de inyección de env (compartidos entre vet y admin)
COPY docker/nginx/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Los volumenes se montan en runtime:
#   /app/vet       → mpc_frontend
#   /app/admin     → admin_mpc
#   /app/clientes  → mpc_clientes

# === Build stage para clientes (Vite) ===
# Se ejecuta en entrypoint.sh

# === Nginx ===
FROM nginx:alpine

# Configuración de Nginx
COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf

# Copiar entrypoint del build stage
COPY --from=build /entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
