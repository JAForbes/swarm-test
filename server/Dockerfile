FROM node:14

WORKDIR /usr/src/app

COPY ./* ./

# RUN npm ci --only=production

EXPOSE 3000

Add Tini
ENV TINI_VERSION v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini
ENTRYPOINT ["/tini", "--"]

CMD [ "node", "app.js" ]