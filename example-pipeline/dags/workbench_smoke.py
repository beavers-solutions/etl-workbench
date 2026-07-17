from __future__ import annotations

import os
from datetime import datetime

from airflow.providers.amazon.aws.hooks.s3 import S3Hook
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.sdk import Param, dag, get_current_context, task
from example_pipeline.messages import build_message


@dag(
    dag_id="workbench_runtime_smoke",
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    params={"message": Param("hello", type="string", minLength=1, maxLength=100)},
    tags=["workbench", "smoke"],
)
def runtime_smoke():
    @task
    def create_message() -> dict[str, str]:
        context = get_current_context()
        return build_message(context["params"]["message"])

    @task
    def log_message(payload: dict[str, str]) -> None:
        print(payload["message"])

    log_message(create_message())


@dag(
    dag_id="workbench_storage_smoke",
    schedule=None,
    start_date=datetime(2026, 1, 1),
    catchup=False,
    params={
        "postgres_conn_id": Param("local_postgres", type="string"),
        "s3_conn_id": Param("local_s3", type="string"),
        "bucket": Param(os.environ.get("ETL_LOCAL_BUCKET", "etl-local"), type="string"),
    },
    tags=["workbench", "smoke"],
)
def storage_smoke():
    @task
    def check_postgres() -> None:
        conn_id = get_current_context()["params"]["postgres_conn_id"]
        row = PostgresHook(postgres_conn_id=conn_id).get_first("SELECT 1")
        if row != (1,):
            raise RuntimeError(f"unexpected PostgreSQL result: {row!r}")

    @task
    def check_object_store() -> None:
        params = get_current_context()["params"]
        hook = S3Hook(aws_conn_id=params["s3_conn_id"])
        if not hook.check_for_bucket(params["bucket"]):
            raise RuntimeError(f"bucket does not exist: {params['bucket']}")

    check_postgres() >> check_object_store()


runtime_smoke()
storage_smoke()
