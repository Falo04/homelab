{{- define "tailnet-node.hostname" -}}
{{- required "hostname is required" .Values.hostname -}}
{{- end -}}

{{- define "tailnet-node.fqdn" -}}
{{- printf "%s.%s" (include "tailnet-node.hostname" .) .Values.domain -}}
{{- end -}}

{{- define "tailnet-node.tlsSecret" -}}
{{- include "tailnet-node.hostname" . }}-tls
{{- end -}}

{{/* Name of a component's resources: <release>-<component>. */}}
{{- define "tailnet-node.fullname" -}}
{{- printf "%s-%s" .ctx.Release.Name .component | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "tailnet-node.labels" -}}
helm.sh/chart: {{ .ctx.Chart.Name }}-{{ .ctx.Chart.Version }}
{{ include "tailnet-node.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .ctx.Release.Service }}
{{- end -}}

{{- define "tailnet-node.selectorLabels" -}}
app.kubernetes.io/name: {{ .ctx.Chart.Name }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}
