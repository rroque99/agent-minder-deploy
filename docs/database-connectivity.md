# Appendix — Database Connectivity (production / Customer Database Mode)

The demo deployment uses the bundled MySQL from `ssp-infra` (`db.enabled=true`),
so there is no database connectivity to configure. For production (Customer
Database Mode), set `db.enabled=false` on `ssp-infra` and point the `ssp` chart
at your own externally managed database.

Supported: MySQL 8.0 / 8.4 and Aurora MySQL 8.0, PostgreSQL 14.19 / 15.14 /
17.7, Oracle 19c.

## 1. Prepare the database

MySQL example — create the database, a `mysql_native_password` user, and grants:

```bash
export SCHEMA_NAME=iamauth; export SCHEMA_USER=iamauth; export SCHEMA_PWD=<db_user_password>
kubectl run -it --rm --image=mysql:8.0.26 --restart=Never mysql-client -- \
  mysql -h<db_host_fqdn> -u<db_admin_user> -p<db_admin_password> \
  -e "CREATE DATABASE IF NOT EXISTS ${SCHEMA_NAME}; \
      CREATE USER IF NOT EXISTS ${SCHEMA_USER} IDENTIFIED WITH mysql_native_password BY '${SCHEMA_PWD}'; \
      GRANT ALL ON ${SCHEMA_NAME}.* TO ${SCHEMA_USER};"
```

## 2. Store the password in a Secret

```bash
kubectl create secret generic ssp-db-credentials \
  --from-literal=mysql-password='<db_user_password>' -n "${NAMESPACE}"
```

## 3. Disable the bundled database on `ssp-infra`

In `values/ssp-infra-override.yaml`:

```yaml
db:
  enabled: false
```

## 4. Point the `ssp` chart at your database

In `values/ssp-override.production.yaml`, either the `jdbcUrl` form already in
that file, or the discrete form:

```yaml
ssp:
  db:
    type: mysql                 # mysql | postgresql | oracle
    serviceHost: <db-host-fqdn>
    servicePort: 3306           # postgresql 5432 · oracle 1521 (SSL 2484)
    schema: iamauth
    name: iamauth
    user: iamauth
    existingSecret: ssp-db-credentials   # Kubernetes secret; key: mysql-password
    sslMode: REQUIRED           # or VERIFY_CA / VERIFY_IDENTITY (+ existingSslSecret)
```

## Notes

- The password must come from `existingSecret` or a Vault-injected file
  (`existingVaultFolder`) — never inline in production.
- On Azure Database for MySQL, set the server timezone to UTC (`"+00:00"`).
- `ssp-data` (Lab 7) reuses the `ssp` chart's DB secret
  (`ssp.db.existingSecret`) and does not create its own — point it at the same
  secret name.
