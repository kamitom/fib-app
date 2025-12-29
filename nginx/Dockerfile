FROM node:lts-alpine3.23 AS builder

WORKDIR /app

COPY fib-fe/package*.json ./fib-fe/
RUN npm --prefix fib-fe install

COPY fib-fe ./fib-fe
RUN npm --prefix fib-fe run build

FROM nginx:1.27-alpine

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/fib-fe/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
