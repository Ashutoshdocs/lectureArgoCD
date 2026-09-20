# Build:  docker build --build-arg APP_VERSION=1.0.0 -t <acr>.azurecr.io/frontend:1.0.0 .
FROM node:20-alpine

WORKDIR /app

# Install deps first for better layer caching
COPY package*.json ./
RUN npm install --omit=dev

# App source
COPY server.js ./

# Version baked in at build time so the running pod reports its tag
ARG APP_VERSION=0.0.0-dev
ENV APP_VERSION=$APP_VERSION
ENV PORT=3000

EXPOSE 3000

# Run as non-root
USER node

CMD ["node", "server.js"]
