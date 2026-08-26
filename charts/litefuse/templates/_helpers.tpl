{{/*
Expand the name of the chart.
*/}}
{{- define "litefuse.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "litefuse.fullname" -}}
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
{{- define "litefuse.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "litefuse.labels" -}}
helm.sh/chart: {{ include "litefuse.chart" . }}
{{ include "litefuse.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "litefuse.selectorLabels" -}}
app.kubernetes.io/name: {{ include "litefuse.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "litefuse.serviceAccountName" -}}
{{- if .Values.litefuse.serviceAccount.create }}
{{- default (include "litefuse.fullname" .) .Values.litefuse.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.litefuse.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Fullname of an aliased sub-chart, computed the way the sub-chart's own
fullname helper does (postgres, valkey, and seaweedfs all share the standard
pattern, with the dependency alias as the chart name). This is what the
sub-chart names its Service, so hostname helpers must use it — the parent's
own fullname prefix only coincides with it when the release is named
"litefuse". Takes (list $ "<alias>").
*/}}
{{- define "litefuse.subchart.fullname" -}}
{{- $ctx := index . 0 -}}
{{- $alias := index . 1 -}}
{{- $vals := index $ctx.Values $alias -}}
{{- if $vals.fullnameOverride -}}
{{- $vals.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default $alias $vals.nameOverride -}}
{{- if contains $name $ctx.Release.Name -}}
{{- $ctx.Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" $ctx.Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Names of the chart-managed auth Secrets for the bundled stores. The
sub-charts read these names from plain values (Helm cannot template
sub-chart values), so the values keys are the single source of truth and
the Secret templates create whatever name they hold. Note: because the
default names are static, two releases of this chart in one namespace need
these keys overridden to disambiguate.
*/}}
{{- define "litefuse.postgresql.authSecretName" -}}
{{- .Values.postgresql.settings.existingSecret | default "litefuse-postgresql-auth" -}}
{{- end -}}

{{- define "litefuse.redis.authSecretName" -}}
{{- .Values.redis.auth.usersExistingSecret | default "litefuse-redis-auth" -}}
{{- end -}}

{{- define "litefuse.s3.authSecretName" -}}
{{- (((.Values.s3.allInOne).s3).existingConfigSecret) | default "litefuse-s3-auth" -}}
{{- end -}}

{{/*
Return PostgreSQL hostname
*/}}
{{- define "litefuse.postgresql.hostname" -}}
{{- if .Values.postgresql.host }}
{{- .Values.postgresql.host }}
{{- else if .Values.postgresql.deploy }}
{{- include "litefuse.subchart.fullname" (list . "postgresql") -}}
{{- end }}
{{- end }}

{{/*
Return Redis hostname
*/}}
{{- define "litefuse.redis.hostname" -}}
{{- if .Values.redis.host }}
{{- .Values.redis.host }}
{{- else if .Values.redis.deploy }}
{{- include "litefuse.subchart.fullname" (list . "redis") -}}
{{- end }}
{{- end }}

{{/* ==========================================================================
   Doris helpers
   ========================================================================== */}}

{{/*
Name of the DorisCluster CR created when doris.deploy is true. The Doris
Operator derives Service names from it: <clusterName>-fe-service /
<clusterName>-be-service.
*/}}
{{- define "litefuse.doris.clusterName" -}}
{{ include "litefuse.fullname" . }}-doris
{{- end -}}

{{/*
Doris FE hostname (MySQL protocol + HTTP). External host wins; otherwise the
operator-managed FE Service of the bundled cluster.
*/}}
{{- define "litefuse.doris.hostname" -}}
{{- if .Values.doris.host -}}
{{- .Values.doris.host -}}
{{- else if .Values.doris.deploy -}}
{{- include "litefuse.doris.clusterName" . }}-fe-service
{{- end -}}
{{- end -}}

{{/*
Doris FE HTTP URL used for Stream Load and the migration runner
(DORIS_FE_HTTP_URL). doris.feHttpUrl overrides verbatim (use it for managed
Doris where the HTTP endpoint differs from <host>:<httpPort>).
*/}}
{{- define "litefuse.doris.feHttpUrl" -}}
{{- if .Values.doris.feHttpUrl -}}
{{- .Values.doris.feHttpUrl -}}
{{- else -}}
http://{{ include "litefuse.doris.hostname" . }}:{{ .Values.doris.httpPort }}
{{- end -}}
{{- end -}}

{{/*
Effective DORIS_REPLICATION_NUM: explicit value wins, otherwise the bundled
cluster caps it at its BE count (a single-BE cluster must create tables with
1 replica), and an external cluster keeps the app default of 3.
*/}}
{{- define "litefuse.doris.replicationNum" -}}
{{- if .Values.doris.replicationNum -}}
{{- .Values.doris.replicationNum -}}
{{- else if .Values.doris.deploy -}}
{{- min 3 (int .Values.doris.cluster.be.replicas) -}}
{{- else -}}
3
{{- end -}}
{{- end -}}

{{/*
Return S3/MinIO endpoint -- if not set uses auto-discovery
*/}}
{{- define "litefuse.s3.endpoint" -}}
{{- if or .Values.s3.eventUpload.endpoint .Values.s3.endpoint }}
{{- .Values.s3.eventUpload.endpoint | default .Values.s3.endpoint }}
{{- else if .Values.s3.deploy }}
{{- /* seaweedfs names the Service <fullname trunc 52>-all-in-one and serves S3 on allInOne.s3.port */ -}}
{{- $swFullname := include "litefuse.subchart.fullname" (list . "s3") | trunc 52 | trimSuffix "-" -}}
{{- printf "http://%s-all-in-one:%v" $swFullname ((((.Values.s3.allInOne).s3).port) | default 8333) -}}
{{- else }}
{{- end }}
{{- end }}

{{/*
Get a value from either a direct value or a secret reference, or nothing if neither is provided
*/}}
{{- define "litefuse.getValueOrSecret" -}}
{{- if (and .value.secretKeyRef.name .value.secretKeyRef.key) -}}
{{- if or .value.value (and .value.fieldRef .value.fieldRef.fieldPath) (and .value.resourceFieldRef .value.resourceFieldRef.resource) -}}
{{- fail (printf ".value, .secretKeyRef, .fieldRef, and .resourceFieldRef are mutually exclusive for %s" .key) -}}
{{- end -}}
valueFrom:
  secretKeyRef:
    name: {{ .value.secretKeyRef.name }}
    key: {{ .value.secretKeyRef.key }}
{{- else if and .value.fieldRef .value.fieldRef.fieldPath -}}
{{- if or .value.value (and .value.secretKeyRef.name .value.secretKeyRef.key) (and .value.resourceFieldRef .value.resourceFieldRef.resource) -}}
{{- fail (printf ".value, .secretKeyRef, .fieldRef, and .resourceFieldRef are mutually exclusive for %s" .key) -}}
{{- end -}}
valueFrom:
  fieldRef:
    fieldPath: {{ .value.fieldRef.fieldPath }}
{{- if .value.fieldRef.apiVersion }}
    apiVersion: {{ .value.fieldRef.apiVersion }}
{{- end }}
{{- else if and .value.resourceFieldRef .value.resourceFieldRef.resource -}}
{{- if or .value.value (and .value.secretKeyRef.name .value.secretKeyRef.key) (and .value.fieldRef .value.fieldRef.fieldPath) -}}
{{- fail (printf ".value, .secretKeyRef, .fieldRef, and .resourceFieldRef are mutually exclusive for %s" .key) -}}
{{- end -}}
valueFrom:
  resourceFieldRef:
    resource: {{ .value.resourceFieldRef.resource }}
{{- if .value.resourceFieldRef.containerName }}
    containerName: {{ .value.resourceFieldRef.containerName }}
{{- end }}
{{- if .value.resourceFieldRef.divisor }}
    divisor: {{ .value.resourceFieldRef.divisor }}
{{- end }}
{{- else if .value.value -}}
value: {{ .value.value | quote }}
{{- end -}}
{{- end -}}

{{/*
    Get a required value from either a direct value or a secret reference
*/}}
{{- define "litefuse.getRequiredValueOrSecret" -}}
{{- with (include "litefuse.getValueOrSecret" .) -}}
{{ . }}
{{- else -}}
{{ fail (printf "no valid value, secretKeyRef, fieldRef, or resourceFieldRef provided for %s" .key) }}
{{- end -}}
{{- end -}}

{{/*
Name of the chart-managed Litefuse application Secret (salt / encryption-key / nextauth-secret).
*/}}
{{- define "litefuse.appSecretName" -}}
{{- printf "%s-app" (include "litefuse.fullname" .) -}}
{{- end -}}

{{/*
Resolve a Litefuse app credential: prefer explicit value / secretKeyRef / fieldRef,
otherwise fall back to the chart-managed `<release>-app` Secret.
*/}}
{{- define "litefuse.getAppSecretValue" -}}
{{- $resolved := include "litefuse.getValueOrSecret" (dict "key" .key "value" .value) -}}
{{- if $resolved -}}
{{- $resolved -}}
{{- else -}}
valueFrom:
  secretKeyRef:
    name: {{ include "litefuse.appSecretName" .root }}
    key: {{ .secretKey | quote }}
{{- end -}}
{{- end -}}

{{/*
Get value of a specific environment variable from additionalEnv if it exists
*/}}
{{- define "litefuse.getEnvVar" -}}
{{- $envVarName := .name -}}
{{- range .env -}}
{{- if eq .name $envVarName -}}
{{ .value }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
    Database related configurations by environment variables.
    The litefuse entrypoint assembles DATABASE_URL as
    postgresql://USER:PASSWORD@HOST/NAME?ARGS — it has no separate port
    handling, so a non-default port must be part of DATABASE_HOST.
*/}}
{{- define "litefuse.databaseEnv" -}}
{{- with (include "litefuse.getEnvVar" (dict "env" .Values.litefuse.additionalEnv "name" "DATABASE_URL")) -}}
{{/*
    If DATABASE_URL is set, we do nothing in databaseEnv.
*/}}
{{- else -}}
- name: DATABASE_HOST
{{- if .Values.postgresql.port }}
  value: {{ printf "%s:%v" (include "litefuse.postgresql.hostname" .) .Values.postgresql.port | quote }}
{{- else }}
  value: {{ include "litefuse.postgresql.hostname" . | quote }}
{{- end }}
{{- if .Values.postgresql.auth.username }}
- name: DATABASE_USERNAME
  value: {{ .Values.postgresql.auth.username | quote }}
{{- end }}
- name: DATABASE_PASSWORD
{{- if .Values.postgresql.auth.existingSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.postgresql.auth.existingSecret }}
      key: {{ required "postgresql.auth.secretKeys.userPasswordKey is required when using an existing secret" .Values.postgresql.auth.secretKeys.userPasswordKey }}
{{- else if .Values.postgresql.deploy }}
  valueFrom:
    secretKeyRef:
      name: {{ include "litefuse.postgresql.authSecretName" . | quote }}
      key: USERDB_PASSWORD
{{- else }}
  value: {{ required "Using an existing secret or postgresql.auth.password is required" .Values.postgresql.auth.password | quote }}
{{- end }}
{{- if .Values.postgresql.auth.database }}
- name: DATABASE_NAME
  value: {{ .Values.postgresql.auth.database | quote }}
{{- end }}
{{- if .Values.postgresql.args }}
- name: DATABASE_ARGS
  value: {{ .Values.postgresql.args | quote }}
{{- end }}
{{- if .Values.postgresql.directUrl }}
- name: DIRECT_URL
  value: {{ .Values.postgresql.directUrl | quote }}
{{- end }}
{{- if .Values.postgresql.shadowDatabaseUrl }}
- name: SHADOW_DATABASE_URL
  value: {{ .Values.postgresql.shadowDatabaseUrl | quote }}
{{- end }}
- name: LITEFUSE_AUTO_POSTGRES_MIGRATION_DISABLED
  value: {{ not .Values.postgresql.migration.autoMigrate | quote }}
{{- end }}
{{- end -}}

{{/*
    Litefuse Server related configurations by environment variables
*/}}
{{- define "litefuse.serverEnv" -}}
- name: NODE_ENV
  value: {{ .Values.litefuse.nodeEnv | quote }}
- name: TZ
  value: {{ .Values.litefuse.timezone | quote }}
- name: LITEFUSE_LOG_LEVEL
  value: {{ .Values.litefuse.logging.level | quote }}
- name: LITEFUSE_LOG_FORMAT
  value: {{ .Values.litefuse.logging.format | quote }}
- name: SALT
  {{- include "litefuse.getAppSecretValue" (dict "root" . "key" "litefuse.salt" "value" .Values.litefuse.salt "secretKey" "salt") | nindent 2 }}
- name: ENCRYPTION_KEY
  {{- include "litefuse.getAppSecretValue" (dict "root" . "key" "litefuse.encryptionKey" "value" .Values.litefuse.encryptionKey "secretKey" "encryption-key") | nindent 2 }}
- name: TELEMETRY_ENABLED
  value: {{ .Values.litefuse.features.telemetryEnabled | quote }}
- name: AUTH_DISABLE_SIGNUP
  value: {{ .Values.litefuse.features.signUpDisabled | quote }}
- name: LITEFUSE_ENABLE_EXPERIMENTAL_FEATURES
  value: {{ .Values.litefuse.features.experimentalFeaturesEnabled | quote }}
- name: LITEFUSE_ENABLE_BACKGROUND_MIGRATIONS
  value: {{ .Values.litefuse.features.backgroundMigrationsEnabled | quote }}
{{- with .Values.litefuse.otelGroup }}
- name: LITEFUSE_OTEL_GROUP_TARGET_BYTES
  value: {{ .targetBytes | int64 | quote }}
- name: LITEFUSE_OTEL_GROUP_TARGET_ROWS
  value: {{ .targetRows | int64 | quote }}
- name: LITEFUSE_OTEL_GROUP_MAX_FILES
  value: {{ .maxFiles | int64 | quote }}
- name: LITEFUSE_OTEL_GROUP_FLUSH_MS
  value: {{ .flushMs | int64 | quote }}
{{- end }}
{{- if hasKey .Values.litefuse "smtp" }}
{{- if .Values.litefuse.smtp.connectionUrl }}
- name: SMTP_CONNECTION_URL
  value: {{ .Values.litefuse.smtp.connectionUrl | quote }}
- name: EMAIL_FROM_ADDRESS
  value: {{ required "litefuse.smtp.fromAddress has to be set if litefuse.smtp.connectionUrl is configured" .Values.litefuse.smtp.fromAddress | quote }}
{{- end }}
{{- end }}
{{- if hasKey .Values.litefuse "allowedOrganizationCreators" }}
{{- if .Values.litefuse.allowedOrganizationCreators }}
- name: LITEFUSE_ALLOWED_ORGANIZATION_CREATORS
  value: {{ join "," .Values.litefuse.allowedOrganizationCreators | quote }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
    NextAuth related configurations by environment variables
*/}}
{{- define "litefuse.nextauthEnv" -}}
- name: NEXTAUTH_URL
  value: {{ .Values.litefuse.nextauth.url | quote }}
- name: NEXTAUTH_SECRET
  {{- include "litefuse.getAppSecretValue" (dict "root" . "key" "litefuse.nextauth.secret" "value" .Values.litefuse.nextauth.secret "secretKey" "nextauth-secret") | nindent 2 }}
{{- if and (hasKey .Values.litefuse "auth") (hasKey .Values.litefuse.auth "disableUsernamePassword") }}
- name: AUTH_DISABLE_USERNAME_PASSWORD
  value: {{ .Values.litefuse.auth.disableUsernamePassword | quote }}
{{- end }}
{{- if and (hasKey .Values.litefuse "auth") (hasKey .Values.litefuse.auth "providers") }}
{{- range $providerName, $provider := .Values.litefuse.auth.providers }}
{{- range $optionKey, $optionVal := $provider }}
- name: AUTH_{{ $providerName | snakecase | upper }}_{{ $optionKey | snakecase | upper }}
{{- if and $optionVal (kindIs "map" $optionVal) }}
  {{- include "litefuse.getValueOrSecret" (dict "key" (printf ".Values.litefuse.auth.providers.%s.%s" $providerName $optionKey) "value" $optionVal) | nindent 2 }}
{{- else if $optionVal }}
  value: {{ $optionVal | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
    Redis related configurations by environment variables
*/}}
{{- define "litefuse.redisEnv" -}}
{{- if or .Values.redis.auth.existingSecret .Values.redis.auth.password .Values.redis.deploy }}
- name: REDIS_PASSWORD
{{- if .Values.redis.auth.existingSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.redis.auth.existingSecret }}
      key: {{ required "redis.auth.existingSecretPasswordKey is required when using an existing secret" .Values.redis.auth.existingSecretPasswordKey }}
{{- else if .Values.redis.deploy }}
  valueFrom:
    secretKeyRef:
      name: {{ include "litefuse.redis.authSecretName" . | quote }}
      key: {{ .Values.redis.auth.username | quote }}
{{- else }}
  value: {{ required "Using an existing secret or redis.auth.password is required" .Values.redis.auth.password | quote }}
{{- end }}
{{- end }}
{{- if .Values.redis.cluster.enabled }}
{{- if not (include "litefuse.getEnvVar" (dict "env" $.Values.litefuse.additionalEnv "name" "REDIS_CLUSTER_NODES")) }}
- name: REDIS_CLUSTER_ENABLED
  value: "true"
- name: REDIS_CLUSTER_NODES
  value: {{ join "," .Values.redis.cluster.nodes | quote }}
{{- if or .Values.redis.auth.existingSecret .Values.redis.auth.password }}
- name: REDIS_AUTH
  value: "$(REDIS_PASSWORD)"
{{- end }}
- name: REDIS_TLS_ENABLED
  value: {{ .Values.redis.tls.enabled | quote }}
{{- if .Values.redis.tls.enabled }}
{{- if .Values.redis.tls.caPath }}
- name: REDIS_TLS_CA_PATH
  value: {{ .Values.redis.tls.caPath | quote }}
{{- end }}
{{- if .Values.redis.tls.certPath }}
- name: REDIS_TLS_CERT_PATH
  value: {{ .Values.redis.tls.certPath | quote }}
{{- end }}
{{- if .Values.redis.tls.keyPath }}
- name: REDIS_TLS_KEY_PATH
  value: {{ .Values.redis.tls.keyPath | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- else if .Values.redis.sentinel.enabled }}
{{- if not (include "litefuse.getEnvVar" (dict "env" $.Values.litefuse.additionalEnv "name" "REDIS_SENTINEL_NODES")) }}
- name: REDIS_SENTINEL_ENABLED
  value: "true"
- name: REDIS_SENTINEL_MASTER_NAME
  value: {{ required "redis.sentinel.masterName is required when sentinel mode is enabled" .Values.redis.sentinel.masterName | quote }}
- name: REDIS_SENTINEL_NODES
  value: {{ required "redis.sentinel.nodes is required when sentinel mode is enabled" .Values.redis.sentinel.nodes | quote }}
{{- if .Values.redis.sentinel.username }}
- name: REDIS_SENTINEL_USERNAME
  value: {{ .Values.redis.sentinel.username | quote }}
{{- end }}
{{- if or .Values.redis.sentinel.existingSecret .Values.redis.sentinel.password }}
- name: REDIS_SENTINEL_PASSWORD
{{- if .Values.redis.sentinel.existingSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.redis.sentinel.existingSecret }}
      key: {{ required "redis.sentinel.existingSecretPasswordKey is required when using an existing secret" .Values.redis.sentinel.existingSecretPasswordKey }}
{{- else }}
  value: {{ .Values.redis.sentinel.password | quote }}
{{- end }}
{{- end }}
{{- if or .Values.redis.auth.existingSecret .Values.redis.auth.password }}
- name: REDIS_AUTH
  value: "$(REDIS_PASSWORD)"
{{- end }}
- name: REDIS_TLS_ENABLED
  value: {{ .Values.redis.tls.enabled | quote }}
{{- if .Values.redis.tls.enabled }}
{{- if .Values.redis.tls.caPath }}
- name: REDIS_TLS_CA_PATH
  value: {{ .Values.redis.tls.caPath | quote }}
{{- end }}
{{- if .Values.redis.tls.certPath }}
- name: REDIS_TLS_CERT_PATH
  value: {{ .Values.redis.tls.certPath | quote }}
{{- end }}
{{- if .Values.redis.tls.keyPath }}
- name: REDIS_TLS_KEY_PATH
  value: {{ .Values.redis.tls.keyPath | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- else }}
{{- if not (include "litefuse.getEnvVar" (dict "env" $.Values.litefuse.additionalEnv "name" "REDIS_CONNECTION_STRING")) }}
- name: REDIS_TLS_ENABLED
  value: {{ .Values.redis.tls.enabled | quote }}
- name: REDIS_CONNECTION_STRING
{{- $hasPassword := or .Values.redis.auth.existingSecret .Values.redis.auth.password .Values.redis.deploy }}
{{- $hasUsername := .Values.redis.auth.username }}
{{- $authPart := "" }}
{{- if and $hasUsername $hasPassword }}
  {{- $authPart = printf "%s:$(REDIS_PASSWORD)@" .Values.redis.auth.username }}
{{- else if $hasPassword }}
  {{- $authPart = ":$(REDIS_PASSWORD)@" }}
{{- else if $hasUsername }}
  {{- $authPart = printf "%s@" .Values.redis.auth.username }}
{{- end }}
  value: "{{ if .Values.redis.tls.enabled }}rediss{{ else }}redis{{ end }}://{{ $authPart }}{{ include "litefuse.redis.hostname" . }}:{{ .Values.redis.port }}/{{ .Values.redis.auth.database }}"
{{- end }}
{{- if .Values.redis.tls.enabled }}
{{- if .Values.redis.tls.caPath }}
- name: REDIS_TLS_CA_PATH
  value: {{ .Values.redis.tls.caPath | quote }}
{{- end }}
{{- if .Values.redis.tls.certPath }}
- name: REDIS_TLS_CERT_PATH
  value: {{ .Values.redis.tls.certPath | quote }}
{{- end }}
{{- if .Values.redis.tls.keyPath }}
- name: REDIS_TLS_KEY_PATH
  value: {{ .Values.redis.tls.keyPath | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
    Doris related configurations by environment variables.
    Mirrors the docker-compose wiring: the entrypoint runs the Doris
    migrations against DORIS_FE_HTTP_URL, the app talks MySQL protocol on
    DORIS_FE_QUERY_PORT and Stream Loads via the FE HTTP port.
*/}}
{{- define "litefuse.dorisEnv" -}}
{{- with (include "litefuse.getEnvVar" (dict "env" .Values.litefuse.additionalEnv "name" "DORIS_FE_HTTP_URL")) -}}
{{/*
  If DORIS_FE_HTTP_URL is set in additionalEnv, we assume all Doris settings
  are configured via additionalEnv and emit nothing here.
*/}}
{{- else -}}
- name: LITEFUSE_ANALYTICS_BACKEND
  value: "doris"
{{- if or .Values.doris.host .Values.doris.feHttpUrl .Values.doris.deploy }}
- name: DORIS_FE_HTTP_URL
  value: {{ include "litefuse.doris.feHttpUrl" . | quote }}
- name: DORIS_URL
  value: {{ include "litefuse.doris.feHttpUrl" . | quote }}
{{- end }}
- name: DORIS_FE_QUERY_PORT
  value: {{ .Values.doris.queryPort | quote }}
- name: DORIS_DB
  value: {{ .Values.doris.database | quote }}
- name: DORIS_USER
  value: {{ .Values.doris.auth.username | quote }}
- name: DORIS_PASSWORD
{{- if .Values.doris.auth.existingSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.doris.auth.existingSecret }}
      key: {{ required "doris.auth.existingSecretKey is required when using an existing secret" .Values.doris.auth.existingSecretKey }}
{{- else }}
  value: {{ .Values.doris.auth.password | quote }}
{{- end }}
- name: DORIS_MAX_OPEN_CONNECTIONS
  value: {{ .Values.doris.maxOpenConnections | int64 | quote }}
- name: DORIS_REQUEST_TIMEOUT_MS
  value: {{ .Values.doris.requestTimeoutMs | int64 | quote }}
- name: DORIS_REPLICATION_NUM
  value: {{ include "litefuse.doris.replicationNum" . | quote }}
- name: LITEFUSE_AUTO_DORIS_MIGRATION_DISABLED
  value: {{ not .Values.doris.migration.autoMigrate | quote }}
- name: LITEFUSE_STORAGE_PAGE_SIZE
  value: {{ .Values.doris.storagePageSize | int64 | quote }}
{{- end }}
{{- end -}}

{{/*
    Get a s3 related config by value or secret. Lookup the bucket value, if not found lookup the shared config.
    If no value or secret is found, return an empty value (e.g. for role IRSA on AWS)
*/}}
{{- define "litefuse.getS3ValueOrSecret" -}}
{{- with (include "litefuse.getValueOrSecret" (dict "key" (printf ".Values.s3.%s.%s" .bucket .key) "value" (index .values .bucket .key)) ) -}}
{{- . }}
{{- else }}
{{- with (include "litefuse.getValueOrSecret" (dict "key" (printf ".Values.s3.%s" .key) "value" (index .values .key)) ) -}}
{{- . }}
{{- else -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
    S3/MinIO related configurations by environment variables
*/}}
{{- define "litefuse.s3Env" -}}
{{/* Storage provider specific environment variables */}}
{{- if eq .Values.s3.storageProvider "azure" }}
- name: LITEFUSE_USE_AZURE_BLOB
  value: "true"
{{- else if eq .Values.s3.storageProvider "gcs" }}
- name: LITEFUSE_USE_GOOGLE_CLOUD_STORAGE
  value: "true"
{{- with (include "litefuse.getValueOrSecret" (dict "key" ".Values.s3.gcs.credentials" "value" .Values.s3.gcs.credentials)) }}
- name: LITEFUSE_GOOGLE_CLOUD_STORAGE_CREDENTIALS
  {{- . | nindent 2 }}
{{- end }}
{{- end }}
- name: LITEFUSE_S3_EVENT_UPLOAD_BUCKET
{{- if $.Values.s3.deploy }}
  value: {{ required "s3.[eventUpload].bucket is required" (coalesce .Values.s3.eventUpload.bucket .Values.s3.bucket .Values.s3.defaultBuckets) | quote }}
{{- else }}
  value: {{ required "s3.[eventUpload].bucket is required" (.Values.s3.eventUpload.bucket | default .Values.s3.bucket) | quote }}
{{- end }}
{{- if .Values.s3.eventUpload.prefix }}
- name: LITEFUSE_S3_EVENT_UPLOAD_PREFIX
  value: {{ .Values.s3.eventUpload.prefix | quote }}
{{- end }}
{{- if or .Values.s3.eventUpload.region .Values.s3.region }}
- name: LITEFUSE_S3_EVENT_UPLOAD_REGION
  value: {{ .Values.s3.eventUpload.region | default .Values.s3.region | quote }}
{{- end }}
{{- if or .Values.s3.eventUpload.endpoint .Values.s3.endpoint .Values.s3.deploy }}
- name: LITEFUSE_S3_EVENT_UPLOAD_ENDPOINT
  value: {{ .Values.s3.eventUpload.endpoint | default .Values.s3.endpoint | default (include "litefuse.s3.endpoint" .) | quote }}
{{- end }}
{{- with (include "litefuse.getS3ValueOrSecret" (dict "key" "accessKeyId" "bucket" "eventUpload" "values" .Values.s3) ) }}
- name: LITEFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID
  {{- . | nindent 2 }}
{{- else }}
{{- if .Values.s3.deploy }}
- name: LITEFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID
  {{- if .Values.s3.auth.existingSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.s3.auth.existingSecret }}
      key: {{ required "s3.auth.rootUserSecretKey is required when s3.auth.existingSecret is set" .Values.s3.auth.rootUserSecretKey }}
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: {{ include "litefuse.s3.authSecretName" . | quote }}
      key: accessKey
  {{- end }}
{{- end }}
{{- end }}
{{- with (include "litefuse.getS3ValueOrSecret" (dict "key" "secretAccessKey" "bucket" "eventUpload" "values" .Values.s3) ) }}
- name: LITEFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY
  {{- . | nindent 2 }}
{{- else }}
{{- if .Values.s3.deploy }}
- name: LITEFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY
  {{- if .Values.s3.auth.existingSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.s3.auth.existingSecret }}
      key: {{ required "s3.auth.rootPasswordSecretKey is required when s3.auth.existingSecret is set" .Values.s3.auth.rootPasswordSecretKey }}
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: {{ include "litefuse.s3.authSecretName" . | quote }}
      key: secretKey
  {{- end }}
{{- end }}
{{- end }}
{{- if or (hasKey .Values.s3.eventUpload "forcePathStyle") (hasKey .Values.s3 "forcePathStyle") }}
- name: LITEFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE
  value: {{ .Values.s3.eventUpload.forcePathStyle | default .Values.s3.forcePathStyle | quote }}
{{- end }}
- name: LITEFUSE_S3_BATCH_EXPORT_ENABLED
  value: {{ .Values.s3.batchExport.enabled | quote }}
{{- if $.Values.s3.batchExport.enabled }}
- name: LITEFUSE_S3_BATCH_EXPORT_BUCKET
{{- if $.Values.s3.deploy }}
  value: {{ required "s3.[batchExport].bucket is required" (coalesce .Values.s3.batchExport.bucket .Values.s3.bucket .Values.s3.defaultBuckets) | quote }}
{{- else }}
  value: {{ required "s3.[batchExport].bucket is required" (.Values.s3.batchExport.bucket | default .Values.s3.bucket) | quote }}
{{- end }}
{{- if or .Values.s3.batchExport.prefix .Values.s3.prefix }}
- name: LITEFUSE_S3_BATCH_EXPORT_PREFIX
  value: {{ .Values.s3.batchExport.prefix | default .Values.s3.prefix | quote }}
{{- end }}
{{- if or .Values.s3.batchExport.region .Values.s3.region }}
- name: LITEFUSE_S3_BATCH_EXPORT_REGION
  value: {{ .Values.s3.batchExport.region | default .Values.s3.region | quote }}
{{- end }}
{{- if or .Values.s3.batchExport.endpoint .Values.s3.endpoint .Values.s3.deploy }}
- name: LITEFUSE_S3_BATCH_EXPORT_ENDPOINT
  value: {{ .Values.s3.batchExport.endpoint | default .Values.s3.endpoint | default (include "litefuse.s3.endpoint" .) | quote }}
{{- end }}
{{- with (include "litefuse.getS3ValueOrSecret" (dict "key" "accessKeyId" "bucket" "batchExport" "values" .Values.s3) ) }}
- name: LITEFUSE_S3_BATCH_EXPORT_ACCESS_KEY_ID
  {{- . | nindent 2 }}
{{- else }}
{{- if .Values.s3.deploy }}
- name: LITEFUSE_S3_BATCH_EXPORT_ACCESS_KEY_ID
  {{- if .Values.s3.auth.existingSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.s3.auth.existingSecret }}
      key: {{ required "s3.auth.rootUserSecretKey is required when s3.auth.existingSecret is set" .Values.s3.auth.rootUserSecretKey }}
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: {{ include "litefuse.s3.authSecretName" . | quote }}
      key: accessKey
  {{- end }}
{{- end }}
{{- end }}
{{- with (include "litefuse.getS3ValueOrSecret" (dict "key" "secretAccessKey" "bucket" "batchExport" "values" .Values.s3) ) }}
- name: LITEFUSE_S3_BATCH_EXPORT_SECRET_ACCESS_KEY
  {{- . | nindent 2 }}
{{- else }}
{{- if .Values.s3.deploy }}
- name: LITEFUSE_S3_BATCH_EXPORT_SECRET_ACCESS_KEY
  {{- if .Values.s3.auth.existingSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.s3.auth.existingSecret }}
      key: {{ required "s3.auth.rootPasswordSecretKey is required when s3.auth.existingSecret is set" .Values.s3.auth.rootPasswordSecretKey }}
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: {{ include "litefuse.s3.authSecretName" . | quote }}
      key: secretKey
  {{- end }}
{{- end }}
{{- end }}
{{- if or (hasKey .Values.s3.batchExport "forcePathStyle") (hasKey .Values.s3 "forcePathStyle") }}
- name: LITEFUSE_S3_BATCH_EXPORT_FORCE_PATH_STYLE
  value: {{ .Values.s3.batchExport.forcePathStyle | default .Values.s3.forcePathStyle | quote }}
{{- end }}
{{- end }}
- name: LITEFUSE_S3_MEDIA_UPLOAD_BUCKET
{{- if $.Values.s3.deploy }}
  value: {{ required "s3.[mediaUpload].bucket is required" (coalesce .Values.s3.mediaUpload.bucket .Values.s3.bucket .Values.s3.defaultBuckets) | quote }}
{{- else }}
  value: {{ required "s3.[mediaUpload].bucket is required" (.Values.s3.mediaUpload.bucket | default .Values.s3.bucket) | quote }}
{{- end }}
{{- if or .Values.s3.mediaUpload.prefix .Values.s3.prefix }}
- name: LITEFUSE_S3_MEDIA_UPLOAD_PREFIX
  value: {{ .Values.s3.mediaUpload.prefix | default .Values.s3.prefix | quote }}
{{- end }}
{{- if or .Values.s3.mediaUpload.region .Values.s3.region }}
- name: LITEFUSE_S3_MEDIA_UPLOAD_REGION
  value: {{ .Values.s3.mediaUpload.region | default .Values.s3.region | quote }}
{{- end }}
{{- if or .Values.s3.mediaUpload.endpoint .Values.s3.endpoint .Values.s3.deploy }}
- name: LITEFUSE_S3_MEDIA_UPLOAD_ENDPOINT
  value: {{ .Values.s3.mediaUpload.endpoint | default .Values.s3.endpoint | default (include "litefuse.s3.endpoint" .) | quote }}
{{- end }}
{{- with (include "litefuse.getS3ValueOrSecret" (dict "key" "accessKeyId" "bucket" "mediaUpload" "values" .Values.s3) ) }}
- name: LITEFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID
  {{- . | nindent 2 }}
{{- else }}
{{- if .Values.s3.deploy }}
- name: LITEFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID
  {{- if .Values.s3.auth.existingSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.s3.auth.existingSecret }}
      key: {{ required "s3.auth.rootUserSecretKey is required when s3.auth.existingSecret is set" .Values.s3.auth.rootUserSecretKey }}
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: {{ include "litefuse.s3.authSecretName" . | quote }}
      key: accessKey
  {{- end }}
{{- end }}
{{- end }}
{{- with (include "litefuse.getS3ValueOrSecret" (dict "key" "secretAccessKey" "bucket" "mediaUpload" "values" .Values.s3) ) }}
- name: LITEFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY
  {{- . | nindent 2 }}
{{- else }}
{{- if .Values.s3.deploy }}
- name: LITEFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY
  {{- if .Values.s3.auth.existingSecret }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.s3.auth.existingSecret }}
      key: {{ required "s3.auth.rootPasswordSecretKey is required when s3.auth.existingSecret is set" .Values.s3.auth.rootPasswordSecretKey }}
  {{- else }}
  valueFrom:
    secretKeyRef:
      name: {{ include "litefuse.s3.authSecretName" . | quote }}
      key: secretKey
  {{- end }}
{{- end }}
{{- end }}
{{- if or (hasKey .Values.s3.mediaUpload "forcePathStyle") (hasKey .Values.s3 "forcePathStyle") }}
- name: LITEFUSE_S3_MEDIA_UPLOAD_FORCE_PATH_STYLE
  value: {{ .Values.s3.mediaUpload.forcePathStyle | default .Values.s3.forcePathStyle | quote }}
{{- end }}
- name: LITEFUSE_S3_MEDIA_MAX_CONTENT_LENGTH
  value: {{ .Values.s3.mediaUpload.maxContentLength | int64 | quote }}
- name: LITEFUSE_S3_MEDIA_DOWNLOAD_URL_EXPIRY_SECONDS
  value: {{ .Values.s3.mediaUpload.downloadUrlExpirySeconds | int64 | quote }}
{{- if hasKey .Values.s3 "concurrency" }}
{{- if hasKey .Values.s3.concurrency "reads" }}
- name: LITEFUSE_S3_CONCURRENT_READS
  value: {{ .Values.s3.concurrency.reads | quote }}
{{- end }}
{{- if hasKey .Values.s3.concurrency "writes" }}
- name: LITEFUSE_S3_CONCURRENT_WRITES
  value: {{ .Values.s3.concurrency.writes | quote }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Common environment variables for all deployments
*/}}
{{- define "litefuse.commonEnv" -}}
{{ include "litefuse.serverEnv" . }}
{{ include "litefuse.nextauthEnv" . }}
{{ include "litefuse.databaseEnv" . }}
{{ include "litefuse.redisEnv" . }}
{{ include "litefuse.dorisEnv" . }}
{{ include "litefuse.s3Env" . }}
{{- end -}}
