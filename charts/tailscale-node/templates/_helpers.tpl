{{- define "tailscale-node.name" -}}
{{- default .Chart.Name .Values.pod.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "tailscale-node.fullname" -}}
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

{{- define "tailscale-node.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "tailscale-node.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "tailscale-node.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tailscale-node.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
