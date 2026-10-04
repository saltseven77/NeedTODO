FROM node:24-alpine
WORKDIR /app
COPY package.json index.mjs backup.mjs ./
ENV HOST=0.0.0.0 PORT=8787 DATABASE=/data/needtodo.sqlite
RUN mkdir /data && chown node:node /data
USER node
VOLUME /data
EXPOSE 8787
CMD ["node", "index.mjs"]
