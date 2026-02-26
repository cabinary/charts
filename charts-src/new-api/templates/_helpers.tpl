{{- define "newapi.name" -}}
new-api
{{- end -}}

{{- define "newapi.fullname" -}}
{{- printf "%s" (include "newapi.name" .) -}}
{{- end -}}

{{- define "newapi.serviceFQDN" -}}
{{- printf "%s.%s.svc.cluster.local" (include "newapi.fullname" .) .Release.Namespace -}}
{{- end -}}

{{- define "newapi.redis.serviceName" -}}
{{- printf "%s-redis" (include "newapi.fullname" .) -}}
{{- end -}}

{{- define "newapi.redis.authSecretName" -}}
{{- if .Values.redis.auth.existingSecret.name -}}
{{- .Values.redis.auth.existingSecret.name -}}
{{- else -}}
{{- printf "%s-redis-auth" (include "newapi.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "newapi.redis.authSecretKey" -}}
{{- default "password" .Values.redis.auth.existingSecret.key -}}
{{- end -}}

{{- define "newapi.database.authSecretName" -}}
{{- if .Values.database.auth.existingSecret.name -}}
{{- .Values.database.auth.existingSecret.name -}}
{{- else -}}
{{- printf "%s-db-auth" (include "newapi.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "newapi.database.authSecretKey" -}}
{{- default "password" .Values.database.auth.existingSecret.key -}}
{{- end -}}

{{- define "newapi.redis.externalAddress" -}}
{{- $host := required "when redis.enabled=false, set env.REDIS_CONN_STRING or redis.host" .Values.redis.host -}}
{{- if contains ":" $host -}}
{{- $host -}}
{{- else -}}
{{- printf "%s:%v" $host (.Values.redis.port | default 6379) -}}
{{- end -}}
{{- end -}}

{{- define "newapi.needsPVC" -}}
{{- if or (not .Values.database.usePostgres) .Values.mountLogs.enabled -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}