# mogambo-charts

One generic Helm chart (`app/`) that renders the Kubernetes objects for **every**
mogambo unit — microservices and databases alike. It is intentionally dumb: it owns
*no* per-service values. Each unit supplies its own values from the
`mogambo-kubernetes` repo (folder `values-<svc>-<ver>/values.yaml`), and ArgoCD
stitches the two together (multi-source) via the ApplicationSet.

## What it renders (all conditional on values)
| Template | Rendered when |
|---|---|
| `deployment.yaml` | `kind: Deployment` |
| `statefulset.yaml` | `kind: StatefulSet` (+ `persistence.enabled` for a PVC) |
| `service.yaml` | `service.enabled` |
| `serviceaccount.yaml` | `serviceAccount.create` |
| `hpa.yaml` | `hpa.enabled` |
| `configmap.yaml` | `config` non-empty |
| `secret.yaml` | `secrets` non-empty |

## Naming
Every object is named `<app>-<versionLine>` (e.g. `frontend-1-0`) and labelled
`app: <app>`, `version: <versionLine>` — so multiple versions of one app coexist.

## Render locally
```bash
helm template frontend-1-0 app/ \
  -f ../mogambo-kubernetes/values-frontend-1-0/values.yaml \
  --namespace mogambo
```

See the full schema in `app/values.yaml`.