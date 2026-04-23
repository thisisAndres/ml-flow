# MLflow Tracking Server (Railway + Postgres + Cloudflare R2)

Self-hosted MLflow Tracking Server for personal MLOps practice:

- **Compute**: Railway (Docker deploy)
- **Backend store**: Railway Postgres (`DATABASE_URL`)
- **Artifact store**: Cloudflare R2 (S3-compatible)
- **Auth**: Basic Auth (via Caddy reverse proxy)

## What you deploy

One container running:

- `mlflow server` bound to `127.0.0.1:5000`
- Caddy listening on `:$PORT` (Railway) with Basic Auth, reverse-proxying to MLflow

## Required environment variables (Railway service)

### Postgres

- `DATABASE_URL`: Railway Postgres connection string

### R2 (artifacts)

- `R2_BUCKET`: bucket name
- `MLFLOW_S3_ENDPOINT_URL`: R2 S3 endpoint URL (example format: `https://<accountid>.r2.cloudflarestorage.com`)
- `AWS_ACCESS_KEY_ID`: R2 access key id
- `AWS_SECRET_ACCESS_KEY`: R2 secret access key
- `AWS_DEFAULT_REGION`: recommended `auto`

Optional:

- `R2_ARTIFACT_PREFIX`: default `mlflow` (artifacts go to `s3://$R2_BUCKET/$R2_ARTIFACT_PREFIX`)
- `AWS_EC2_METADATA_DISABLED`: default `true` (keeps boto3 from trying instance metadata)

### Basic Auth (protect the UI/API)

- `BASIC_AUTH_USER`
- `BASIC_AUTH_PASSWORD`

### Public hostname (MLflow Host / CORS)

Railway gives you a hostname like `your-service.up.railway.app`. MLflow 3.5+ validates the `Host` header (DNS rebinding protection). You must tell the app which hostname is public:

- **`MLFLOW_PUBLIC_HOST`**: hostname only, no scheme or path (example: `ml-flow-production-344b.up.railway.app`)

At startup, `start.sh` sets (unless you override):

- `MLFLOW_SERVER_ALLOWED_HOSTS` → `MLFLOW_PUBLIC_HOST,localhost:*,127.0.0.1:*`
- `MLFLOW_SERVER_CORS_ALLOWED_ORIGINS` → `https://MLFLOW_PUBLIC_HOST`

Optional overrides:

- `MLFLOW_SERVER_ALLOWED_HOSTS`, `MLFLOW_SERVER_CORS_ALLOWED_ORIGINS`: set explicitly if you use a custom domain or multiple origins
- `MLFLOW_USE_GUNICORN=1`: use Gunicorn instead of the default Uvicorn server (not recommended; security middleware behavior differs)
- `MLFLOW_UVICORN_OPTS`: optional extra flags passed to Uvicorn via `mlflow server --uvicorn-opts` (omit unless you need them)

Optional:

- `BASIC_AUTH_PASSWORD_HASH`: if set, the server will use it instead of hashing `BASIC_AUTH_PASSWORD` at startup.

## Railway setup

1. **Create a new project** in Railway.
2. **Add Postgres** to the project.
3. **Create a new Service** from this GitHub repo (Deploy from Dockerfile).
4. In the Service **Variables**, add all env vars listed above.
   - Copy `DATABASE_URL` from the Postgres plugin variables.
   - Set **`MLFLOW_PUBLIC_HOST`** to the same hostname shown in Railway’s public URL (without `https://`).
5. Deploy.
6. Open the Railway public URL.
   - You should get a **Basic Auth prompt**, then the **MLflow UI**.

### Troubleshooting: “Invalid Host header” / DNS rebinding

If the UI shows an error about **Invalid Host header** or **DNS rebinding**:

1. Confirm **`MLFLOW_PUBLIC_HOST`** matches the hostname you use in the browser (e.g. `*.up.railway.app`).
2. After attaching a **custom domain**, update **`MLFLOW_PUBLIC_HOST`** (and optionally set **`MLFLOW_SERVER_CORS_ALLOWED_ORIGINS`** to `https://your-custom-domain`).
3. Avoid **`MLFLOW_USE_GUNICORN=1`** unless you know you need it; the default **Uvicorn** server is what MLflow’s allowed-hosts middleware targets.

## CI/CD

### Continuous integration

GitHub Actions runs on:

- pushes to `dev`
- pull requests targeting `dev` or `master`

Checks:

- ShellCheck (`start.sh`)
- Docker build

### Continuous deployment (Railway)

On every push to `main`, GitHub Actions will deploy using the Railway CLI (`railway up --ci`).

Add these **repository secrets** in GitHub (Settings → Secrets and variables → Actions):

- `RAILWAY_TOKEN` (recommended: a Railway **Project Token** scoped to your **production** environment)
- `RAILWAY_PROJECT_ID`
- `RAILWAY_SERVICE_ID`

Optional:

- `RAILWAY_ENVIRONMENT`: defaults to `production` if unset

## Smoke test (artifact lands in R2)

From your laptop (or any machine with network access to the Railway URL):

```bash
pip install mlflow
export MLFLOW_TRACKING_URI="https://<your-railway-domain>"
export MLFLOW_TRACKING_USERNAME="<BASIC_AUTH_USER>"
export MLFLOW_TRACKING_PASSWORD="<BASIC_AUTH_PASSWORD>"

python - <<'PY'
import mlflow, os, tempfile, pathlib

mlflow.set_tracking_uri(os.environ["MLFLOW_TRACKING_URI"])
mlflow.set_experiment("smoke-test")

with mlflow.start_run():
    mlflow.log_param("hello", "world")
    p = pathlib.Path(tempfile.gettempdir()) / "hello.txt"
    p.write_text("hello r2")
    mlflow.log_artifact(str(p))
    print("run_id:", mlflow.active_run().info.run_id)
PY
```

Then verify in Cloudflare R2 that objects were created under `mlflow/` (or your `R2_ARTIFACT_PREFIX`).

## Local run (optional)

You can run the same container locally if you point it at:

- a reachable Postgres (local or remote) in `DATABASE_URL`
- your R2 bucket credentials and endpoint

Example:

```bash
docker build -t mlflow-railway .
docker run --rm -p 8080:8080 \
  -e PORT=8080 \
  -e MLFLOW_PUBLIC_HOST="localhost" \
  -e DATABASE_URL="postgresql://..." \
  -e R2_BUCKET="your-bucket" \
  -e MLFLOW_S3_ENDPOINT_URL="https://<accountid>.r2.cloudflarestorage.com" \
  -e AWS_ACCESS_KEY_ID="..." \
  -e AWS_SECRET_ACCESS_KEY="..." \
  -e AWS_DEFAULT_REGION="auto" \
  -e BASIC_AUTH_USER="admin" \
  -e BASIC_AUTH_PASSWORD="change-me" \
  mlflow-railway
```

Open `http://localhost:8080` and log in. For local HTTP, you may set `MLFLOW_SERVER_CORS_ALLOWED_ORIGINS=http://localhost:8080` if the UI blocks on CORS.

## Credential rotation

To rotate Basic Auth:

- update `BASIC_AUTH_PASSWORD` (and optionally `BASIC_AUTH_USER`) in Railway variables
- redeploy (or restart) the service

To rotate R2 keys:

- update `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
- redeploy (or restart)

