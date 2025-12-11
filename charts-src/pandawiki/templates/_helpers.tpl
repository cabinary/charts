{{/*
Expand the name of the chart.
*/}}
{{- define "panda-wiki.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "panda-wiki.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "panda-wiki.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "panda-wiki.labels" -}}
helm.sh/chart: {{ include "panda-wiki.chart" . }}
{{ include "panda-wiki.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "panda-wiki.selectorLabels" -}}
app.kubernetes.io/name: {{ include "panda-wiki.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Image registry helper
*/}}
{{- define "panda-wiki.image" -}}
{{- $registry := .global.imageRegistry | default .local.imageRegistry -}}
{{- $image := .local.image -}}
{{- printf "%s/%s" $registry $image -}}
{{- end }}

{{/*
MinIO Endpoint helper
Returns internal K8s service DNS if enabled, otherwise returns configured external host and port.
*/}}
{{- define "panda-wiki.minio.endpoint" -}}
{{- if .Values.minio.enabled -}}
{{ include "panda-wiki.fullname" . }}-minio:9000
{{- else -}}
{{ .Values.minio.externalHost }}:{{ .Values.minio.externalPort }}
{{- end -}}
{{- end }}

{{/*
Postgres Host helper
Returns internal K8s service name if enabled, otherwise returns configured external host.
*/}}
{{- define "panda-wiki.postgres.host" -}}
{{- if .Values.postgres.enabled -}}
{{ include "panda-wiki.fullname" . }}-postgres
{{- else -}}
{{ .Values.postgres.externalHost }}
{{- end -}}
{{- end }}

{{/*
Postgres Port helper
Returns internal K8s service port if enabled, otherwise returns configured external port.
*/}}
{{- define "panda-wiki.postgres.port" -}}
{{- if .Values.postgres.enabled -}}
5432
{{- else -}}
{{ .Values.postgres.externalPort }}
{{- end -}}
{{- end }}
