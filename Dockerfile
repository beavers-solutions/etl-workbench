FROM apache/airflow:slim-3.3.0-python3.12@sha256:16a6aeb38e865627e3f8e96ab0ef82d5de215153b3d8f9f5878a480136a96582

ARG AIRFLOW_VERSION=3.3.0
ARG PYTHON_VERSION=3.12
ARG AIRFLOW_CONSTRAINTS=https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt

COPY --chown=airflow:root requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir \
      --requirement /tmp/requirements.txt \
      --constraint "${AIRFLOW_CONSTRAINTS}" \
    && python -m pip check

USER root
RUN mkdir -p /var/lib/airflow /opt/pipeline/src /opt/airflow/dags \
    && chown -R airflow:root /var/lib/airflow /opt/pipeline /opt/airflow/dags
USER airflow

ENV AIRFLOW_HOME=/var/lib/airflow \
    AIRFLOW__CORE__DAGS_FOLDER=/opt/airflow/dags \
    AIRFLOW__CORE__LOAD_EXAMPLES=False \
    AIRFLOW__CORE__EXECUTOR=LocalExecutor \
    AIRFLOW__CORE__PARALLELISM=4 \
    PYTHONPATH=/opt/pipeline/src

WORKDIR /opt/pipeline

CMD ["airflow", "standalone"]
