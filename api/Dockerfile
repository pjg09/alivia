# El contexto de construccion es la RAIZ del repositorio, no api/, porque
# npm ci con espacios de trabajo necesita el package-lock.json de la raiz.
# El compose lo declara con `context: .` y `dockerfile: api/Dockerfile`.

FROM node:24-alpine AS construccion
WORKDIR /alivia

# Las dependencias primero y solos: asi la capa se reutiliza mientras el
# codigo cambia, que es casi siempre.
COPY package.json package-lock.json ./
COPY api/package.json ./api/
RUN npm ci

COPY api/tsconfig.json ./api/
COPY api/src ./api/src
RUN npm run build --workspace @alivia/api

# --- Imagen final ------------------------------------------------------------
# El servidor no tiene dependencias de ejecucion todavia, solo la biblioteca
# estandar de Node, asi que aqui no entra ni un node_modules. Cuando entre la
# primera (pg, en la tarea 3) hay que copiar tambien las de produccion.
FROM node:24-alpine
WORKDIR /alivia/api
ENV NODE_ENV=production
ENV PUERTO=3000

COPY --from=construccion /alivia/api/dist ./dist

USER node
EXPOSE 3000
CMD ["node", "dist/principal.js"]
