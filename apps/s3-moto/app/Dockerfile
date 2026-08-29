# Built in-cluster by the CI workflow (kaniko) and pushed to k3d-registry:5000.
FROM python:3.12-slim

RUN pip install --no-cache-dir boto3==1.35.36

WORKDIR /app
COPY main.py .

EXPOSE 8080
USER 65534
ENTRYPOINT ["python", "/app/main.py"]
