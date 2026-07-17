# ETL Workbench

A small local Apache Airflow workbench for trusted, code-defined ETL pipelines.
It provides orchestration and optional local PostgreSQL and S3-compatible object
storage. Pipeline code, schemas, migrations, and data lifecycle rules stay in a
separate repository.

This is a single-user development tool. It is not a shared scheduler, control
plane, deployment system, or isolation boundary for untrusted DAG code.

## Requirements

- Docker Desktop or Docker Engine with Compose
- at least 4 GB of memory available to Docker
- a pipeline repository containing `dags/`, `src/`, and `pyproject.toml`

The included `example-pipeline` satisfies that contract and is the default.

## Start

Airflow only, with connections configured for external services:

```bash
cp .env.example .env
docker build -t etl-workbench:local .
docker compose up airflow
```

Fully local:

```bash
docker build -t etl-workbench:local .
docker compose --profile local-db --profile local-objects up
```

Mixed modes enable exactly one profile:

```bash
docker compose --profile local-db up
docker compose --profile local-objects up
```

Open <http://127.0.0.1:18080>. The generated local login is stored inside the
`airflow-home` volume:

```bash
docker compose exec airflow \
  cat /var/lib/airflow/simple_auth_manager_passwords.json.generated
```

Local profile connection IDs are `local_postgres` and `local_s3`; the local
bucket is `etl-local`. For external systems, create any required connections in
the Airflow UI or override the connection environment variables in `.env`.
The UI's connection test is intentionally disabled because runtime hooks are
the authoritative check, including for S3-compatible services.
Pipelines that require local SSE-S3 may set their own development-only
`MINIO_KMS_SECRET_KEY` in the ignored `.env` file.

## Attach a pipeline repository

Set an absolute path in `.env`:

```dotenv
PIPELINE_ROOT=/absolute/path/to/my-pipeline
PIPELINE_ENV_FILE=/absolute/path/to/my-pipeline/pipeline.env
```

Expected layout:

```text
my-pipeline/
├── dags/
├── src/
└── pyproject.toml
```

The `dags/` and `src/` directories are mounted read-only. A missing directory
fails startup instead of silently creating an empty mount. Airflow discovers
all compatible DAGs in `dags/`, while `/opt/pipeline/src` is on `PYTHONPATH`.
The optional environment file is pipeline-owned and must never be committed
when it contains credentials.

Pipeline-specific dependencies belong in a derived image, never in a runtime
`pip install`:

```dockerfile
FROM etl-workbench:local

COPY --chown=airflow:root pyproject.toml /tmp/pipeline/pyproject.toml
COPY --chown=airflow:root src /tmp/pipeline/src
RUN pip install --no-cache-dir /tmp/pipeline
```

Build it and set `AIRFLOW_IMAGE` in `.env`:

```bash
docker build -t my-pipeline-airflow:local -f Dockerfile.airflow .
```

```dotenv
AIRFLOW_IMAGE=my-pipeline-airflow:local
```

The pipeline repository owns its database schema and migrations, retry and
idempotency behavior, object keys and buckets, retention, and business logic.
This repository owns none of those contracts.

## Verify

Validate topology and imports:

```bash
docker compose config --quiet
docker compose --profile local-db config --quiet
docker compose --profile local-objects config --quiet
docker compose --profile local-db --profile local-objects config --quiet
docker build -t etl-workbench:local .
docker compose run --rm airflow python -c \
  'from airflow.models import DagBag; b=DagBag("/opt/airflow/dags"); assert not b.import_errors, b.import_errors'
```

With both local services running, execute the neutral runtime and storage DAGs:

```bash
docker compose --profile local-db --profile local-objects up -d
docker compose exec airflow airflow dags test workbench_runtime_smoke 2026-01-01
docker compose exec airflow airflow dags test workbench_storage_smoke 2026-01-01
```

Use small serializable values in XCom. Persist real datasets in PostgreSQL or
object storage and pass references between tasks.

## Stop

Keep local history and data:

```bash
docker compose --profile local-db --profile local-objects down
```

Explicitly delete all workbench volumes:

```bash
docker compose --profile local-db --profile local-objects down --volumes
```

Scheduled runs stop when the laptop or Compose stack stops. Shared scheduling,
remote Airflow metadata, multiple isolated pipeline environments, distributed
executors, monitoring, and untrusted DAG execution are outside v1.

## License

Apache-2.0. See `LICENSE`.
