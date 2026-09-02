FROM node:18-bullseye
WORKDIR /app
ADD app/package.json app/package-lock.json ./
RUN npm ci --omit=dev
ADD app/server.js ./
EXPOSE 3000
CMD ["node", "server.js"]
