{{/* <app>-<versionLine> (e.g. frontend-1-0), or fullnameOverride for singletons like DBs (catalogue-db) */}}
{{- define "app.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride -}}
{{- else -}}
{{- printf "%s-%s" .Values.app .Values.versionLine -}}
{{- end -}}
{{- end -}}

{{/* Labels / selector. `version` is included only for versioned units (apps); singletons (DBs) omit it. */}}
{{- define "app.labels" -}}
app: {{ .Values.app }}
{{- if .Values.versionLine }}
version: {{ .Values.versionLine | quote }}
{{- end }}
{{- end -}}