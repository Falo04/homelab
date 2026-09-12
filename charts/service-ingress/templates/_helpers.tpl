{{- define "service-ingress.name" -}}
{{- default .Chart.Name .Values.pod.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "service-ingress.fullname" -}}
{{- if .Values.pod.fullnameOverride -}}
{{- .Values.pod.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.pod.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "service-ingress.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "service-ingress.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "service-ingress.selectorLabels" -}}
app.kubernetes.io/name: {{ include "service-ingress.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
