FROM registry.access.redhat.com/ubi9/nodejs-20:latest

WORKDIR /opt/app-root/src

COPY services/api-gateway/package.json ./
RUN npm install --omit=dev

COPY services/api-gateway/server.js ./

ENV NODE_ENV=production
EXPOSE 8080

CMD ["npm", "start"]
