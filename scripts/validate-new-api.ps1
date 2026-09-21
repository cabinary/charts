param(
    [string]$ChartPath = "charts-src/new-api"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$chartFullPath = Join-Path $repoRoot $ChartPath

if (-not (Test-Path $chartFullPath)) {
    throw "Chart path not found: $chartFullPath"
}

if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    throw "helm command not found in PATH."
}

function Assert-Contains {
    param(
        [string]$Content,
        [string]$Needle,
        [string]$Message
    )

    if ($Content -notmatch [regex]::Escape($Needle)) {
        throw "Assertion failed: $Message`nMissing: $Needle"
    }
}

function Render-Template {
    param(
        [string]$Scenario,
        [string[]]$SetArgs = @()
    )

    Write-Host "[template] $Scenario" -ForegroundColor Cyan
    $args = @("template", "new-api", $chartFullPath) + $SetArgs
    $output = & helm @args 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "helm template failed for scenario '$Scenario'`n$output"
    }
    return $output
}

Write-Host "[check] helm lint" -ForegroundColor Cyan
$lintOutput = & helm lint $chartFullPath 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "helm lint failed`n$lintOutput"
}

# 读取 appVersion，验证默认 image.tag 回退逻辑
$chartMeta = & helm show chart $chartFullPath 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "helm show chart failed`n$chartMeta"
}
$appVersionLine = ($chartMeta -split "`r?`n" | Where-Object { $_ -match '^appVersion:' } | Select-Object -First 1)
$appVersion = ($appVersionLine -replace '^appVersion:\s*', '').Trim('"')
if ([string]::IsNullOrWhiteSpace($appVersion)) {
    throw "Unable to parse appVersion from chart metadata."
}

# 1) 默认渲染
$defaultYaml = Render-Template -Scenario "default"
Assert-Contains -Content $defaultYaml -Needle ("image: ""calciumion/new-api:{0}""" -f $appVersion) -Message "default image tag should fallback to appVersion"
Assert-Contains -Content $defaultYaml -Needle "name: SQL_DSN" -Message "default should include SQL_DSN env when database.usePostgres=true"

# 2) Ingress 场景
$ingressYaml = Render-Template -Scenario "ingress" -SetArgs @(
    "--set", "ingress.enabled=true",
    "--set", "route.hosts[0]=new-api.example.com"
)
Assert-Contains -Content $ingressYaml -Needle "kind: Ingress" -Message "Ingress resource should be rendered"
Assert-Contains -Content $ingressYaml -Needle 'ingressClassName: "alb"' -Message "Ingress className should default to alb"
Assert-Contains -Content $ingressYaml -Needle 'ingress-controller: "alb"' -Message "Ingress label ingress-controller should follow className"

# 3) Istio VirtualService 场景
$istioYaml = Render-Template -Scenario "istio" -SetArgs @(
    "--set", "istio.enabled=true",
    "--set", "route.hosts[0]=new-api.example.com",
    "--set", "istio.virtualService.gateways[0]=istio-system/panda-wiki-gateway"
)
Assert-Contains -Content $istioYaml -Needle "kind: VirtualService" -Message "VirtualService resource should be rendered"
Assert-Contains -Content $istioYaml -Needle "- istio-system/panda-wiki-gateway" -Message "VirtualService should contain configured gateway"

# 4) 多域名 + route.tls 复用到 Ingress
$multiHostYaml = Render-Template -Scenario "multihost+route.tls" -SetArgs @(
    "--set", "ingress.enabled=true",
    "--set", "route.hosts[0]=codex.example.com",
    "--set", "route.hosts[1]=claude.example.com",
    "--set", "route.hosts[2]=gemini.example.com",
    "--set", "route.tls[0].secretName=example-tls",
    "--set", "route.tls[0].hosts[0]=codex.example.com",
    "--set", "route.tls[0].hosts[1]=claude.example.com",
    "--set", "route.tls[0].hosts[2]=gemini.example.com"
)
Assert-Contains -Content $multiHostYaml -Needle '- host: "codex.example.com"' -Message "Ingress should render codex host"
Assert-Contains -Content $multiHostYaml -Needle '- host: "claude.example.com"' -Message "Ingress should render claude host"
Assert-Contains -Content $multiHostYaml -Needle 'secretName: "example-tls"' -Message "Ingress should reuse route.tls secret"

# 5) 数据库密码从 existingSecret 注入
$dbSecretYaml = Render-Template -Scenario "db-auth-secret" -SetArgs @(
    "--set", "database.auth.existingSecret.name=my-db-secret",
    "--set", "database.auth.password="
)
Assert-Contains -Content $dbSecretYaml -Needle "name: DB_PASSWORD" -Message "DB_PASSWORD env should be rendered for existingSecret"
Assert-Contains -Content $dbSecretYaml -Needle "name: my-db-secret" -Message "DB_PASSWORD should reference configured secret"
Assert-Contains -Content $dbSecretYaml -Needle 'postgresql://root:$(DB_PASSWORD)@' -Message "SQL_DSN should use DB_PASSWORD variable when existingSecret is set"

# 6) 单机 updater：RBAC 权限、自动 deadline、digest 回滚脚本
$updaterYaml = Render-Template -Scenario "updater-single" -SetArgs @(
    "--set", "updater.enabled=true"
)
Assert-Contains -Content $updaterYaml -Needle 'resources: ["controllerrevisions"]' -Message "updater Role should allow reading controllerrevisions"
Assert-Contains -Content $updaterYaml -Needle 'verbs: ["get", "list", "watch", "delete"]' -Message "updater Role should allow deleting pods for forced rollback"
Assert-Contains -Content $updaterYaml -Needle "activeDeadlineSeconds: 720" -Message "single mode deadline should be 1 x 2 x 300 + 120"
Assert-Contains -Content $updaterYaml -Needle 'IMAGE_REF="calciumion/new-api:' -Message "updater script should carry the floating image ref"
Assert-Contains -Content $updaterYaml -Needle 'rollout_statefulset "new-api" master || exit 1' -Message "single mode should roll out the new-api StatefulSet"
Assert-Contains -Content $updaterYaml -Needle "delete_unready_pods" -Message "updater script should delete not-ready pods on rollback"

# 7) 集群 updater + PrometheusRule
$clusterMonYaml = Render-Template -Scenario "cluster+updater+prometheusrule" -SetArgs @(
    "-f", (Join-Path $chartFullPath "values-cluster.yaml"),
    "--set", "updater.enabled=true",
    "--set", "monitoring.prometheusRule.enabled=true",
    "--set", "monitoring.prometheusRule.labels.release=kps"
)
Assert-Contains -Content $clusterMonYaml -Needle "activeDeadlineSeconds: 1320" -Message "cluster mode deadline should be 2 x 2 x 300 + 120"
Assert-Contains -Content $clusterMonYaml -Needle 'rollout_statefulset "new-api-master" master || {' -Message "cluster mode should roll out master first"
Assert-Contains -Content $clusterMonYaml -Needle 'rollout_statefulset "new-api-slave" slave || exit 1' -Message "cluster mode should roll out slave after master"
Assert-Contains -Content $clusterMonYaml -Needle "kind: PrometheusRule" -Message "PrometheusRule should be rendered when enabled"
Assert-Contains -Content $clusterMonYaml -Needle "release: kps" -Message "PrometheusRule should carry configured labels"
Assert-Contains -Content $clusterMonYaml -Needle 'statefulset=~"^(new-api-master|new-api-slave)$"' -Message "PrometheusRule should target both cluster StatefulSets"
Assert-Contains -Content $clusterMonYaml -Needle "alert: NewApiUpdaterJobFailed" -Message "PrometheusRule should include updater failure alert when updater is enabled"

# 8) 显式 activeDeadlineSeconds 优先于自动计算
$deadlineYaml = Render-Template -Scenario "updater-explicit-deadline" -SetArgs @(
    "--set", "updater.enabled=true",
    "--set", "updater.activeDeadlineSeconds=900"
)
Assert-Contains -Content $deadlineYaml -Needle "activeDeadlineSeconds: 900" -Message "explicit updater.activeDeadlineSeconds should win over auto calculation"

Write-Host "All new-api validations passed." -ForegroundColor Green
