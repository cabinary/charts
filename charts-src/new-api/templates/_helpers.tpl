{{- define "newapi.name" -}}
new-api
{{- end -}}

{{- define "newapi.fullname" -}}
{{- printf "%s" (include "newapi.name" .) -}}
{{- end -}}

{{- define "newapi.headlessServiceName" -}}
{{- printf "%s-headless" (include "newapi.fullname" .) -}}
{{- end -}}

{{- define "newapi.masterStatefulSetName" -}}
{{- printf "%s-master" (include "newapi.fullname" .) -}}
{{- end -}}

{{- define "newapi.slaveStatefulSetName" -}}
{{- printf "%s-slave" (include "newapi.fullname" .) -}}
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

{{- define "newapi.updater.serviceAccountName" -}}
{{- printf "%s-updater" (include "newapi.fullname" .) -}}
{{- end -}}

{{- define "newapi.updater.roleName" -}}
{{- printf "%s-updater" (include "newapi.fullname" .) -}}
{{- end -}}

{{- define "newapi.updater.roleBindingName" -}}
{{- printf "%s-updater" (include "newapi.fullname" .) -}}
{{- end -}}

{{- define "newapi.updater.cronJobName" -}}
{{- printf "%s-updater" (include "newapi.fullname" .) -}}
{{- end -}}

{{- define "newapi.validate" -}}
{{- if .Values.cluster.enabled -}}
  {{- if ne (int .Values.cluster.master.replicas) 1 -}}
    {{- fail "cluster.master.replicas must be 1 when cluster.enabled=true" -}}
  {{- end -}}
  {{- if lt (int .Values.cluster.slave.replicas) 1 -}}
    {{- fail "cluster.slave.replicas must be at least 1 when cluster.enabled=true" -}}
  {{- end -}}
  {{- if not .Values.database.usePostgres -}}
    {{- fail "database.usePostgres must be true when cluster.enabled=true; all nodes must share one writable database" -}}
  {{- end -}}

  {{- $env := default (dict) .Values.env -}}
  {{- $secretName := default "" .Values.envFromSecret.name -}}
  {{- $secretKeys := default (dict) .Values.envFromSecret.keys -}}
  {{- $hasSessionSecret := false -}}
  {{- if hasKey $env "SESSION_SECRET" -}}
    {{- $hasSessionSecret = ne (printf "%v" (index $env "SESSION_SECRET")) "" -}}
  {{- end -}}
  {{- if and (ne $secretName "") (hasKey $secretKeys "SESSION_SECRET") -}}
    {{- $hasSessionSecret = true -}}
  {{- end -}}
  {{- if not $hasSessionSecret -}}
    {{- fail "cluster mode requires SESSION_SECRET in env or envFromSecret" -}}
  {{- end -}}

  {{- $hasCryptoSecret := false -}}
  {{- if hasKey $env "CRYPTO_SECRET" -}}
    {{- $hasCryptoSecret = ne (printf "%v" (index $env "CRYPTO_SECRET")) "" -}}
  {{- end -}}
  {{- if and (ne $secretName "") (hasKey $secretKeys "CRYPTO_SECRET") -}}
    {{- $hasCryptoSecret = true -}}
  {{- end -}}
  {{- if not $hasCryptoSecret -}}
    {{- fail "cluster mode requires CRYPTO_SECRET in env or envFromSecret because all chart-managed nodes share one Redis endpoint" -}}
  {{- end -}}

  {{- if and .Values.mountLogs.enabled (not .Values.persistence.existingClaim) (not (has "ReadWriteMany" .Values.persistence.accessModes)) -}}
    {{- fail "cluster mode with mountLogs.enabled=true requires persistence.accessModes to include ReadWriteMany, or an existing RWX claim" -}}
  {{- end -}}
{{- end -}}
{{- end -}}
