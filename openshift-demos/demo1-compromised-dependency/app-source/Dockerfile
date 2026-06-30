FROM registry.access.redhat.com/ubi8/nodejs-16:latest

WORKDIR /opt/app-root/src

COPY package.json ./
RUN npm install

COPY app.js ./

EXPOSE 8080

CMD ["node", "app.js"]
