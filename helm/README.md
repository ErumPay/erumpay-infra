# ErumPay Helm charts

## Generic service chart

All backend services use the common chart:

```bash
helm upgrade --install payment-service ./helm/charts/erumpay-service \
  -n pay --create-namespace \
  -f ./helm/values/dev/payment-service.yaml
```

Render locally before applying:

```bash
helm template payment-service ./helm/charts/erumpay-service \
  -n pay \
  -f ./helm/values/dev/payment-service.yaml
```

## Dev values

The files under `helm/values/dev` are templates. Replace:

- `<AWS_ACCOUNT_ID>`
- `<RDS_ENDPOINT>`
- `<DB_USERNAME>`
- `<DB_PASSWORD>`

before deploying to the dev cluster.

## Namespace guide

- `pay`: user-facing backend services
- `pg`: PG backend services
- `middleware`: Kafka, Redis, shared middleware
- `platform-operations`: gateway, ingress/controller operations
