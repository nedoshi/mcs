FROM registry.access.redhat.com/ubi9/nodejs-20:latest

WORKDIR /opt/app-root/src

COPY services/shared ./shared
COPY services/catalog-service/package.json ./
RUN npm install --omit=dev

COPY services/catalog-service/server.js ./

ENV NODE_ENV=production
EXPOSE 8081

CMD ["npm", "start"]
