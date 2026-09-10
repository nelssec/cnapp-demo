# Intentionally weak image for the CNAPP demo: end-of-life base image, ADD from a URL,
# no USER, no HEALTHCHECK, bundled ML model, customer fixtures and payment config.
FROM node:16-buster
# Build-time knob only used for local builds behind TLS-intercepting proxies.
ARG NPM_CONFIG_STRICT_SSL=true
ENV NPM_CONFIG_STRICT_SSL=${NPM_CONFIG_STRICT_SSL}
WORKDIR /app
ADD app/package.json app/package-lock.json ./
RUN npm ci --omit=dev
ADD app/server.js ./
# Log4Shell (CVE-2021-44228, CISA KEV) pulled straight from Maven Central at build time
ADD https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-core/2.14.1/log4j-core-2.14.1.jar /app/lib/
ADD models/huggingface/transformers/ /root/.cache/huggingface/transformers/
ADD service/fixtures/ /app/data/
ADD service/config/ /app/config/
EXPOSE 3000
CMD ["node", "server.js"]
