{{/*
templates/_helpers.tpl

Named templates used across all chart manifests.
Define once here, reference everywhere with {{ include "my-service.X" . }}

Why this matters:
  Labels defined here are used in both Deployment.spec.selector.matchLabels
  AND in topologySpreadConstraints.labelSelector.matchLabels.
  If these diverge, topology spread silently stops working.
  Centralising them here makes divergence impossible.
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "my-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncated to 63 characters — Kubernetes label value limit.
If release name contains the chart name, avoid duplication.
*/}}
{{- define "my-service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart label — used in helm.sh/chart label.
*/}}
{{- define "my-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to every resource this chart creates.
Enables: kubectl get all -l helm.sh/chart=my-service-0.1.0
*/}}
{{- define "my-service.labels" -}}
helm.sh/chart: {{ include "my-service.chart" . }}
{{ include "my-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels — used in:
  - Deployment.spec.selector.matchLabels  (IMMUTABLE after first deploy)
  - Service.spec.selector
  - topologySpreadConstraints.labelSelector.matchLabels
  - PodDisruptionBudget.spec.selector.matchLabels
  - HPA.spec.scaleTargetRef (indirectly via Deployment name)

WARNING: selector labels on a Deployment are immutable.
Changing them requires deleting and recreating the Deployment.
This is why they live here and nowhere else — one source of truth.
*/}}
{{- define "my-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "my-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name.
Uses .Values.serviceAccount.name if set, otherwise fullname.
*/}}
{{- define "my-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "my-service.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference — combines repository and tag.
Fails with a clear error if image.tag is not set.
In CI: always pass --set image.tag=sha-xxxxxxx
*/}}
{{- define "my-service.image" -}}
{{- if not .Values.image.tag }}
{{- fail "image.tag must be set — use --set image.tag=YOUR_IMAGE_SHA" }}
{{- end }}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end }}

{{/*
Topology spread constraints with selector labels injected.
The labelSelector must match the pod's selector labels exactly.
Defining this as a named template ensures it always stays in sync
with selectorLabels — you cannot accidentally use different labels.
*/}}
{{- define "my-service.topologySpreadConstraints" -}}
{{- range .Values.topologySpreadConstraints }}
- maxSkew: {{ .maxSkew }}
  topologyKey: {{ .topologyKey }}
  whenUnsatisfiable: {{ .whenUnsatisfiable }}
  labelSelector:
    matchLabels:
      {{- include "my-service.selectorLabels" $ | nindent 6 }}
{{- end }}
{{- end }}
