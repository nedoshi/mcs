FROM registry.access.redhat.com/ubi9/nodejs-20:latest

WORKDIR /opt/app-root/src

COPY services/shared ./shared
COPY services/cart-service/package.json ./
RUN npm install --omit=dev

COPY services/cart-service/server.js ./

ENV NODE_ENV=production
EXPOSE 8082

CMD ["npm", "start"]
