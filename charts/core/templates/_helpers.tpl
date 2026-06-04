{{/*
Render template values inside the values.yaml file.
Usage: {{ include "cluster-core.render" (dict "val" .Values.path "context" $) }}
*/}}
{{- define "cluster-core.render" -}}
    {{- $val := .val -}}
    {{- $context := .context -}}
    {{- if kindIs "string" $val -}}
        {{- tpl $val $context -}}
    {{- else -}}
        {{- $val -}}
    {{- end -}}
{{- end -}}