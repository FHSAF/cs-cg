{{/*
Render a value through Go templating if it is a string, otherwise pass through.
Usage: {{ include "opensource-services.render" (dict "val" .Values.path "context" $) }}
*/}}
{{- define "opensource-services.render" -}}
    {{- $val := .val -}}
    {{- $context := .context -}}
    {{- if kindIs "string" $val -}}
        {{- tpl $val $context -}}
    {{- else -}}
        {{- $val | toYaml -}}
    {{- end -}}
{{- end -}}

{{/*
Generate the conventional value-file path for an app (used when chart.valueFiles is not set).
Convention: $values/clusters/<projectName>/<environment>/values/<valuesDir>/<appName>-values.yaml
valuesDir defaults to "opensource-services" when not set on the app.
Usage: {{ include "opensource-services.defaultValuesFile" (dict "appName" "valkey" "valuesDir" "valkey" "context" $) }}
*/}}
{{- define "opensource-services.defaultValuesFile" -}}
{{- $projectName := tpl .context.Values.projectName .context -}}
{{- $environment := tpl .context.Values.environment .context -}}
{{- $dir := .valuesDir | default "opensource-services" -}}
{{- printf "$values/clusters/%s/%s/values/%s/%s-values.yaml" $projectName $environment $dir .appName -}}
{{- end -}}

{{/*
Render the helm chart source entry.
Emits the primary chart source block with auto-convention value file support.

chart fields:
  repoURL         (required) helm chart repository URL
  targetRevision  (required) chart version / revision
  name            (required) chart name inside the repo
  valueFiles      (optional) explicit list of value files; if absent the convention path is used
  extraValueFiles (optional) extra value files appended after the main value file
  values          (optional) inline helm values block
  parameters      (optional) list of helm parameter overrides

Usage: {{ include "opensource-services.chartSource" (dict "app" $appConfig "appName" $appName "context" $) }}
*/}}
{{- define "opensource-services.chartSource" -}}
{{- $app  := .app -}}
{{- $name := .appName -}}
{{- $ctx  := .context -}}
{{- $c    := $app.chart -}}
- repoURL: {{ include "opensource-services.render" (dict "val" $c.repoURL "context" $ctx) }}
  targetRevision: {{ include "opensource-services.render" (dict "val" $c.targetRevision "context" $ctx) }}
  chart: {{ $c.name }}
  helm:
    valueFiles:
    {{- if $c.valueFiles }}
      {{- range $c.valueFiles }}
      - {{ include "opensource-services.render" (dict "val" . "context" $ctx) }}
      {{- end }}
    {{- else }}
      - {{ include "opensource-services.defaultValuesFile" (dict "appName" $name "valuesDir" $app.valuesDir "context" $ctx) }}
    {{- end }}
    {{- range $c.extraValueFiles }}
      - {{ include "opensource-services.render" (dict "val" . "context" $ctx) }}
    {{- end }}
    {{- if $c.values }}
    values: |
      {{- include "opensource-services.render" (dict "val" $c.values "context" $ctx) | nindent 6 }}
    {{- end }}
    {{- if $c.parameters }}
    parameters:
      {{- toYaml $c.parameters | nindent 6 }}
    {{- end }}
{{- end -}}

{{/*
Render a local (selfRepo path-based) helm chart source entry.
Similar to chartSource but sources the chart from a path inside the same repo.
Auto-generates the convention value-file path (respects valuesDir).

localChart fields:
  path            (required) path to the chart inside the repo
  valueFiles      (optional) explicit list; if absent the convention path is used
  extraValueFiles (optional) extra value files appended after main valueFiles
  values          (optional) inline helm values block
  parameters      (optional) list of helm parameter overrides

Usage: {{ include "opensource-services.localChartSource" (dict "app" $appConfig "appName" $appName "context" $) }}
*/}}
{{- define "opensource-services.localChartSource" -}}
{{- $app  := .app -}}
{{- $name := .appName -}}
{{- $ctx  := .context -}}
{{- $lc   := $app.localChart -}}
- repoURL: {{ $ctx.Values.repoURL }}
  targetRevision: {{ $ctx.Values.targetRevision }}
  path: {{ $lc.path }}
  helm:
    valueFiles:
    {{- if $lc.valueFiles }}
      {{- range $lc.valueFiles }}
      - {{ include "opensource-services.render" (dict "val" . "context" $ctx) }}
      {{- end }}
    {{- else }}
      - {{ include "opensource-services.defaultValuesFile" (dict "appName" $name "valuesDir" $app.valuesDir "context" $ctx) }}
    {{- end }}
    {{- range $lc.extraValueFiles }}
      - {{ include "opensource-services.render" (dict "val" . "context" $ctx) }}
    {{- end }}
    {{- if $lc.values }}
    values: |
      {{- include "opensource-services.render" (dict "val" $lc.values "context" $ctx) | nindent 6 }}
    {{- end }}
    {{- if $lc.parameters }}
    parameters:
      {{- toYaml $lc.parameters | nindent 6 }}
    {{- end }}
{{- end -}}

{{/*
Render the values-ref source (always injected alongside a chart source so that
$values can be used in helm valueFiles references).
Always uses the global $.Values.repoURL and $.Values.targetRevision.
Usage: {{ include "opensource-services.valuesRefSource" (dict "context" $) }}
*/}}
{{- define "opensource-services.valuesRefSource" -}}
{{- $ctx := .context -}}
- repoURL: {{ $ctx.Values.repoURL }}
  targetRevision: {{ $ctx.Values.targetRevision }}
  ref: values
{{- end -}}

{{/*
Render a generic source entry (used for extraSources and the escape-hatch sources list).

Supported fields: repoURL, targetRevision, chart, name (alias for chart),
path, ref, directory, helm.valueFiles, helm.extraValueFiles, helm.values, helm.parameters

Usage: {{ include "opensource-services.genericSource" (dict "source" $src "context" $) }}
*/}}
{{- define "opensource-services.genericSource" -}}
{{- $s   := .source -}}
{{- $ctx := .context -}}
- repoURL: {{ include "opensource-services.render" (dict "val" $s.repoURL "context" $ctx) }}
  targetRevision: {{ include "opensource-services.render" (dict "val" $s.targetRevision "context" $ctx) }}
  {{- if (or $s.chart $s.name) }}
  chart: {{ coalesce $s.chart $s.name }}
  {{- end }}
  {{- if $s.path }}
  path: {{ include "opensource-services.render" (dict "val" $s.path "context" $ctx) }}
  {{- end }}
  {{- if $s.ref }}
  ref: {{ $s.ref }}
  {{- end }}
  {{- if $s.directory }}
  directory:
    {{- toYaml $s.directory | nindent 4 }}
  {{- end }}
  {{- if $s.helm }}
  helm:
    {{- if $s.helm.valueFiles }}
    valueFiles:
      {{- range $s.helm.valueFiles }}
      - {{ include "opensource-services.render" (dict "val" . "context" $ctx) }}
      {{- end }}
    {{- end }}
    {{- range $s.helm.extraValueFiles }}
      - {{ include "opensource-services.render" (dict "val" . "context" $ctx) }}
    {{- end }}
    {{- if $s.helm.values }}
    values: |
      {{- include "opensource-services.render" (dict "val" $s.helm.values "context" $ctx) | nindent 6 }}
    {{- end }}
    {{- if $s.helm.parameters }}
    parameters:
      {{- toYaml $s.helm.parameters | nindent 6 }}
    {{- end }}
  {{- end }}
{{- end -}}
