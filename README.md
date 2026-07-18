# ETL Workbench

A small local Apache Airflow workbench for trusted, code-defined ETL pipelines.
It runs Airflow and, when requested, local PostgreSQL and S3-compatible object
storage. Pipeline code and data contracts stay in their own repositories.

This is a single-user development tool. It is not a shared scheduler, control
plane, deployment platform, or isolation boundary for untrusted DAG code.

## Requirements

- Docker Desktop or Docker Engine with Compose
- at least 4 GB of memory available to Docker
- a pipeline Git repository containing `dags/`
- `Dockerfile.airflow` in that repository when the pipeline needs its own image

## Start a Git pipeline

For a public repository:

```bash
./bin/etl-workbench https://github.com/example/acme-pipeline.git
```

For a private SSH repository:

```bash
./bin/etl-workbench git@github.com:example/acme-pipeline.git \
  --ssh-key ~/.ssh/id_ed25519
```

The command builds the workbench image, builds the pipeline's
`Dockerfile.airflow`, configures Airflow's native `GitDagBundle`, starts local
PostgreSQL and object storage, and waits for the services to become healthy.
Airflow then clones and refreshes the DAG bundle itself. Each task run records
the Git version of the DAG code that produced it.

Open <http://127.0.0.1:18080>. The generated local login is stored inside the
`airflow-home` volume:

```bash
docker compose exec airflow \
  cat /var/lib/airflow/simple_auth_manager_passwords.json.generated
```

To expose only the authenticated Airflow UI on a trusted local network, set
`AIRFLOW_UI_HOST=0.0.0.0` when starting the launcher. Database and object-store
ports keep their localhost-only defaults.

Useful options:

```text
--ref VERSION            branch, tag, or commit; default: main
--subdir PATH            DAG directory; default: dags
--image IMAGE            use a prebuilt pipeline image
--env FILE               pipeline-owned runtime environment
--external-db            do not start local PostgreSQL
--external-objects       do not start local object storage
--git-connection ID      use an existing Airflow Git connection
```

With `--ssh-key`, the launcher writes a generated Airflow connection to the
ignored `.workbench/runtime.env` with mode `0600`. The private key is used by
Docker BuildKit and the local Airflow container; it is not copied into the
image. Host-key checking uses `~/.ssh/known_hosts` by default.

## Pipeline repository contract

The smallest repository contains one or more DAG files:

```text
acme-pipeline/
├── dags/
│   └── pipeline.py
└── Dockerfile.airflow
```

A pipeline image can add Python packages or application code:

```dockerfile
ARG ETL_WORKBENCH_IMAGE=etl-workbench:local
FROM ${ETL_WORKBENCH_IMAGE}

COPY --chown=airflow:root pyproject.toml src/ /tmp/pipeline/
RUN pip install --no-cache-dir /tmp/pipeline
```

The launcher overrides `ETL_WORKBENCH_IMAGE` with the locally built workbench
image. Runtime secrets belong in an ignored pipeline environment file and are
passed with `--env`; never bake them into the image or DAG files.

Airflow discovers compatible DAGs from the Git bundle and displays them in its
UI. The pipeline repository owns schemas and migrations, retry and idempotency
behavior, object keys and retention, and all business logic.

Local profile connection IDs are `local_postgres` and `local_s3`; the local
bucket is `etl-local`. External connections may be created in the Airflow UI or
provided as `AIRFLOW_CONN_*` variables in the pipeline environment file.

## LLM connections

The workbench image includes the Airflow OpenAI provider. Create each provider
as an independent `openai` Connection in the Airflow UI; its **Password** is
the provider-specific API key. Use the **Host** field for the OpenAI client's
base URL (or set `openai_client_kwargs.base_url` in Extra).

| Connection ID | Host |
| --- | --- |
| `llm_kimi` | `https://api.moonshot.ai/v1` |
| `llm_deepseek` | `https://api.deepseek.com` |
| `llm_qwen` | Model Studio endpoint for the selected region and workspace |
| `llm_mistral` | `https://api.mistral.ai/v1` |

Pipeline code selects the `conn_id` and model name. It must not contain API
keys. For portability across these providers, use the Chat Completions API and
avoid OpenAI-specific APIs unless that pipeline is intentionally tied to
OpenAI.

## Local path development

The included example can be mounted read-only without Git:

```bash
docker build -t etl-workbench:local .
docker compose -f compose.yaml -f compose.local.yaml \
  --profile local-db --profile local-objects up
```

Set `PIPELINE_ROOT` to use another local repository. This fallback expects both
`dags/` and `src/`; GitDagBundle is the normal repository integration.

## Verify

```bash
docker compose config --quiet
docker compose -f compose.yaml -f compose.local.yaml config --quiet
docker build -t etl-workbench:local .
docker compose -f compose.yaml -f compose.local.yaml run --rm airflow python -c \
  'from airflow.models import DagBag; b=DagBag("/opt/airflow/dags"); assert not b.import_errors, b.import_errors'
```

## Stop

Keep local history and data:

```bash
docker compose --profile local-db --profile local-objects down
```

Explicitly delete workbench volumes and generated Git credentials:

```bash
docker compose --profile local-db --profile local-objects down --volumes
rm -rf .workbench
```

Scheduled runs stop when the laptop or Compose stack stops. Shared scheduling,
remote Airflow metadata, distributed executors, monitoring, and untrusted DAG
execution are outside this workbench's scope.

## License

Apache-2.0. See `LICENSE`.
