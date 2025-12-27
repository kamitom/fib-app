FROM node:lts-alpine3.23

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

# 生產預設：直接執行
CMD ["npm", "run", "start"]
