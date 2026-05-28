# project Microservices - Deployment

This document explains the new approach for deploying project microservices using a single ApplicationSet and unified values file.

## Overview

Instead of maintaining individual ArgoCD Application files and separate values files for each microservice, this solution uses:

1. **One ApplicationSet**: `clusters/project/dev/microservices/project-microservices.yaml`
2. **One values file**: `clusters/project/dev/microservices/values/project-microservices-values.yaml`
3. **Enhanced ms chart**: Supports multi-microservice configuration

## How It Works

### ApplicationSet

The ApplicationSet generates individual Applications for each microservice listed in its generators:

```yaml
generators:
- list:
    elements:
    - name: project-booking-classifier
    - name: project-doc-classifier
    # ... more microservices
```

Each generated Application:
- Uses the same `charts/ms` chart
- References the same `project-microservices-values.yaml` file
- Passes `nameOverride: {{ .name }}` to lookup its specific configuration

### Unified Values File

The values file structure:

```yaml
global:
  # Shared configuration for all microservices
  image:
    pullSecret: "harbor-pull-secret-project-ds"
    repositoryBase: "harbor.tecomon.net/project/"
  tenant: "dev"
  microserviceDb: true
  microserviceRmq: true

microservices:
  project-booking-classifier:
    replicaCount: 1
    image:
      tag: "0.1.0-main.19"
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
    service:
      port: 80
      targetPort: 8181
    ingress:
      enabled: true
      host: "booking-classifier.dev.app.tecomon.dev"
    # ... more config
  
  project-doc-classifier:
    # ... config
```

### Chart Enhancement

The `ms` chart now includes a helper function `mychart.getConfig` that:
1. Looks up the microservice config using `nameOverride`
2. Merges it with global defaults
3. Returns the final configuration for templates to use

## Adding a New Microservice

To add a new microservice:

1. **Add to ApplicationSet** (`clusters/project/dev/microservices/project-microservices.yaml`):
   ```yaml
   - name: project-new-service
   ```

2. **Add configuration** to `clusters/project/dev/values/project-microservices-values.yaml`:
   ```yaml
   microservices:
     project-new-service:
       replicaCount: 1
       image:
         tag: "0.1.0-main.1"
       resources:
         limits:
           cpu: 500m
           memory: 512Mi
       service:
         port: 80
         targetPort: 8080
       ingress:
         enabled: false
       serviceAccount:
         create: true
         name: "project-new-service-sa"
       environment: {}
   ```

3. Commit and push - ArgoCD will automatically deploy the new service!

## Benefits

✅ **Reduced Boilerplate**: One ApplicationSet vs 15+ Application files  
✅ **Centralized Configuration**: All microservice configs in one file  
✅ **Easy to Add Services**: Just add a name and config block  
✅ **Consistent Defaults**: Global settings applied to all services  
✅ **Better Overview**: See all microservices and their configs at a glance  
✅ **Version Control Friendly**: Single file changes are easier to review  

## Configuration Reference

### Global Settings

Applied to all microservices unless overridden:

- `global.image.pullSecret`: Image pull secret name
- `global.image.repositoryBase`: Base container registry URL
- `global.tenant`: Tenant identifier for secret lookups
- `global.microserviceDb`: Enable database environment variables
- `global.microserviceRmq`: Enable RabbitMQ environment variables

### Per-Microservice Settings

Each microservice can override any value:

- `replicaCount`: Number of pod replicas
- `deploymentStrategy`: Raw Kubernetes Deployment strategy block
- `image.tag`: Container image tag
- `resources`: CPU/memory requests and limits
- `service`: Service configuration (port, targetPort)
- `ingress`: Ingress configuration (enabled, host, TLS, annotations)
- `serviceAccount`: Service account configuration
- `environment`: Structured environment variables
- `keda`: Auto-scaling configuration
- `microserviceDb`: Override global DB settings
- `microserviceRmq`: Override global RabbitMQ settings

Example to force old pods to terminate before new ones are created:

```yaml
microservices:
  project-account:
    deploymentStrategy:
      type: Recreate
```

### Environment Variables

The chart automatically injects:

**When `microserviceDb: true`:**
- `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`
- `DATABASE_USER`, `DATABASE_PASSWORD`

**When `microserviceRmq: true`:**
- `RABBITMQ_HOST_EDA`, `RABBITMQ_HOST`, `RABBITMQ_PORT`
- `RABBITMQ_USER`, `RABBITMQ_VHOST`, `RABBITMQ_PASSWORD`

**Custom environment variables:**
```yaml
environment:
  EXECUTION:
    ENV:
      value: "dev"
  REDIS:
    HOST:
      valueFrom:
        secretKeyRef:
          name: "dev-microservices-redis-secrets"
          key: redis-host
```

