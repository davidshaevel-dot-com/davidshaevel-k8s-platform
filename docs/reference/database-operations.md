# Database Operations

Quick reference for interacting with the PostgreSQL database in the davidshaevel-website deployment.

---

## Connecting

### From Portainer Console

1. Portainer → AKS environment → Namespaces → davidshaevel-website
2. Click the database pod → Console icon → connect
3. Run: `psql -U postgres -d davidshaevel`

### From kubectl

```bash
kubectl exec -it -n davidshaevel-website deployment/database -- psql -U postgres -d davidshaevel
```

---

## Common psql Commands

```sql
-- List all tables
\dt

-- Show table structure (columns, types, constraints)
\d <table_name>

-- Count rows in a table
SELECT count(*) FROM <table_name>;

-- View first 10 rows
SELECT * FROM <table_name> LIMIT 10;

-- List all databases
\l

-- Current connection info
\conninfo

-- Quit
\q
```

---

## Notes

- **Schema management:** TypeORM with `synchronize: true` (development mode) auto-creates and updates tables from entity definitions. No manual migrations needed.
- **Data persistence:** PostgreSQL data is stored on an Azure managed disk PVC (`postgres-data`, 1Gi). Data survives pod restarts and cluster stop/start cycles.
- **Credentials:** `postgres` / `postgres` (development only — would use External Secrets Operator for production).
