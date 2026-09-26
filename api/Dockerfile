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

# --- Dependencias de ejecucion, sin las de desarrollo ------------------------
# Aparte del build a proposito: asi la imagen final no lleva TypeScript, tsx ni
# Biome, que no hacen falta para correr y son la mayor parte del peso.
FROM node:24-alpine AS dependencias
WORKDIR /alivia
COPY package.json package-lock.json ./
COPY api/package.json ./api/
RUN npm ci --omit=dev

# --- Imagen final ------------------------------------------------------------
FROM node:24-alpine
WORKDIR /alivia/api
ENV NODE_ENV=production
ENV PUERTO=3000

# Los espacios de trabajo suben las dependencias a la raiz, y `node` las
# resuelve hacia arriba desde /alivia/api.
COPY --from=dependencias /alivia/node_modules /alivia/node_modules
COPY --from=dependencias /alivia/package.json /alivia/package.json
COPY --from=construccion /alivia/api/package.json ./package.json
COPY --from=construccion /alivia/api/dist ./dist

USER node
EXPOSE 3000
CMD ["node", "dist/principal.js"]
