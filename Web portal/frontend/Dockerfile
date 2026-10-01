# RoadGuard web portal, built and served by nginx (service "web" in the
# repository's docker-compose.yml). nginx also passes /api/ and /static/ to
# the backend, so the portal, the API and the phone app share one address.

# --- Stage 1: build the React app ------------------------------------------
FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
# The API is on the same address as the portal (nginx proxies /api/), so a
# relative URL works wherever the site is opened.
ENV VITE_API_URL=/api/v1
RUN npm run build

# --- Stage 2: serve the built files ------------------------------------------
FROM nginx:1.29-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
