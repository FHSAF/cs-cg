{{/*
=============================================================================
Get Microservice Config Helper
=============================================================================
This helper merges global config with microservice-specific config.
If nameOverride is set, it looks up config from .Values.microservices[nameOverride]
and merges it with root values, with microservice-specific values taking precedence.
*/}}
{{- define "mychart.getConfig" -}}
{{- $global := .Values.global | default dict -}}
{{- /* Start with a deep copy of values */ -}}
{{- $config := deepCopy .Values -}}

{{- /* 1. Force Global Tenant if present, overwriting the default 'tenant' */ -}}
{{- if $global.tenant -}}
  {{- $_ := set $config "tenant" $global.tenant -}}
{{- end -}}

{{- /* 1b. Promote global deployment strategy into the root config. */ -}}
{{- if $global.deploymentStrategy -}}
  {{- $_ := set $config "deploymentStrategy" $global.deploymentStrategy -}}
{{- end -}}

{{- /* 2. Merge Microservice specific config (which can override global tenant) */ -}}
{{- if .Values.nameOverride -}}
  {{- if and .Values.microservices (hasKey .Values.microservices .Values.nameOverride) -}}
    {{- $msConfig := index .Values.microservices .Values.nameOverride -}}
    {{- $config = mergeOverwrite $config $msConfig -}}
  {{- end -}}
{{- end -}}

{{- /* 3. Normalize image settings from global.image after the microservice merge. */ -}}
{{- if $global.image -}}
  {{- $imageConfig := $config.image | default dict -}}
  {{- $_ := set $config "image" (mergeOverwrite $imageConfig $global.image) -}}
{{- end -}}

{{- $config | toJson -}}
{{- end -}}

{{- define "mychart.resolvePlatformTag" -}}
{{- $tag := .tag | default "" -}}
{{- $version := .platformVersion | default "" -}}
{{- $channel := .channel | default "" -}}
{{- if and $tag $version (eq $channel "stable") (not (contains "-prod" $tag)) -}}
{{- printf "%s-prod.%s" $tag $version -}}
{{- else -}}
{{- $tag -}}
{{- end -}}
{{- end -}}

{{- define "mychart.supportingImageRef" -}}
{{- $tag := include "mychart.resolvePlatformTag" (dict "tag" .tag "platformVersion" .platformVersion "channel" .channel) -}}
{{- if and .repository $tag -}}
{{- printf "%s:%s" .repository $tag -}}
{{- end -}}
{{- end -}}
{{/*
Helper to get a value from the merged config
*/}}
{{- define "mychart.getValue" -}}
{{- $configJson := include "mychart.getConfig" . -}}
{{- $config := $configJson | fromJson -}}
{{- $path := .path -}}
{{- $parts := split "." $path -}}
{{- $value := $config -}}
{{- range $parts -}}
  {{- if hasKey $value . -}}
    {{- $value = index $value . -}}
  {{- else -}}
    {{- $value = "" -}}
  {{- end -}}
{{- end -}}
{{- $value -}}
{{- end -}}

{{/*
=============================================================================
Environment Variables Helper
=============================================================================
This template renders a list of environment variables for a container.
It processes the structured 'environment' map, a simple 'extraEnvs' list,
and includes common DATABASE and RABBITMQ variables based on feature flags.

Usage:
{{- include "mychart.environmentVariables" . | nindent 8 }}
*/}}
{{- define "mychart.environmentVariables" -}}
{{- if or .Values.environment .Values.extraEnvs .Values.microserviceDb .Values.microserviceRmq }}
env:
{{- /* Conditionally include DATABASE env vars */}}
{{- if .Values.microserviceDb }}
  - name: DATABASE_HOST
    valueFrom:
      secretKeyRef:
        # name: {{ .Values.tenant }}-microservices-postgresql-secrets
        name: pg-connection-secrets
        key: host-pooler-tx
  - name: DATABASE_PORT
    valueFrom:
      secretKeyRef:
        name: pg-connection-secrets
        key: port
  - name: DATABASE_NAME
    valueFrom:
      secretKeyRef:
        name: pg-connection-secrets
        key: dbname
  - name: DATABASE_USER
    valueFrom:
      secretKeyRef:
        name: pg-microservice-secrets
        key: username
  - name: DATABASE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: pg-microservice-secrets
        key: password
{{- end }}

{{- /* Conditionally include RABBITMQ env vars */}}
{{- if .Values.microserviceRmq }}
  - name: RABBITMQ_HOST_EDA
    valueFrom:
      secretKeyRef:
        # name: {{ .Values.tenant }}-microservices-rabbitmq-secrets
        name: rabbitmq-keda-secrets
        key: https-host-full
  - name: RABBITMQ_HOST
    valueFrom:
      secretKeyRef:
        name: rabbitmq-connection-secrets
        key: amqps-host
  - name: RABBITMQ_PORT
    valueFrom:
      secretKeyRef:
        name: rabbitmq-connection-secrets
        key: amqps-port
  - name: RABBITMQ_USER
    valueFrom:
      secretKeyRef:
        name: rabbitmq-microservice-secrets
        key: username
  - name: RABBITMQ_VHOST
    valueFrom:
      secretKeyRef:
        name: rabbitmq-microservice-secrets
        key: vhost
  - name: RABBITMQ_PASSWORD
    valueFrom:
      secretKeyRef:
        name: rabbitmq-microservice-secrets
        key: password
{{- end }}

{{- /* Original loop for structured 'environment' map */}}
{{- range $typeName, $vars := .Values.environment }}
  {{- range $varName, $varConfig := $vars }}
  - name: {{ $typeName | upper }}_{{ $varName | upper }}
    {{- if $varConfig.value }}
    value: {{ $varConfig.value | quote }}
    {{- else if $varConfig.valueFrom }}
    valueFrom:
      {{- toYaml $varConfig.valueFrom | nindent 6 }}
    {{- end }}
  {{- end }}
{{- end }}

{{- /* Original loop for 'extraEnvs' list */}}
{{- range .Values.extraEnvs }}
  - name: {{ .name }}
    {{- if .value }}
    value: {{ .value | quote }}
    {{- else if .valueFrom }}
    valueFrom:
      {{- toYaml .valueFrom | nindent 6 }}
    {{- end }}
{{- end }}
{{- end }}
{{- end -}}
