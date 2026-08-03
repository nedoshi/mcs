FROM registry.access.redhat.com/ubi9/nodejs-20:latest

WORKDIR /opt/app-root/src

COPY services/frontend/package.json ./
RUN npm install --omit=dev

COPY services/frontend/server.js ./
COPY services/frontend/public ./public

ENV NODE_ENV=production
EXPOSE 8080

CMD ["npm", "start"]
