# Custom CloudNativePG Postgres image with pg_partman.
# Tag must start with the PostgreSQL major version for CNPG auto-detection.
#
# "bookworm" is the Debian 12 codename used by the CNPG image variant
# (…-standard-bookworm). It is not a Postgres version; PG version is 17.5.
ARG PG_VERSION=17.5
FROM ghcr.io/cloudnative-pg/postgresql:${PG_VERSION}-standard-bookworm

USER root
RUN apt-get update \
  && apt-get install -y --no-install-recommends "postgresql-17-partman" \
  && rm -rf /var/lib/apt/lists/*

# CNPG images remapped postgres to UID 26 (see cloudnative-pg/postgres-containers).
# Official custom-image docs require ending as USER 26 so the operator's
# non-root securityContext matches. Do not leave the image as root.
USER 26
