FROM registry.access.redhat.com/ubi9/nodejs-20:latest

WORKDIR /opt/app-root/src

COPY services/shared ./shared
COPY services/order-service/package.json ./
RUN npm install --omit=dev

COPY services/order-service/server.js ./

ENV NODE_ENV=production
EXPOSE 8083

CMD ["npm", "start"]
