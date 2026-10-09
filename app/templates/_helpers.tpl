{{/* <app>-<versionLine>, e.g. frontend-1-0 */}}
{{- define "app.fullname" -}}
{{- printf "%s-%s" .Values.app .Values.versionLine -}}
{{- end -}}

{{/* Common labels / selector (app + version together identify one version line) */}}
{{- define "app.labels" -}}
app: {{ .Values.app }}
version: {{ .Values.versionLine | quote }}
{{- end -}}