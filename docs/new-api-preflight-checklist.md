# new-api 安装前检查清单（Preflight）

适用目录：`charts-src/new-api`

## 1) 基础环境检查

- [ ] Helm 版本建议 `v3.12+`
- [ ] 已连接目标 Kubernetes 集群，且当前 context 正确
- [ ] 目标 namespace 已确认（示例使用 `default`）
- [ ] 集群支持 `batch/v1` CronJob（用于 `updater`）

可执行命令：

```powershell
kubectl config current-context
kubectl version --short
helm version
```

## 2) values 关键项检查

- [ ] `image.pullPolicy: Always`（已默认）
- [ ] `env.TZ` 已设置为预期时区（例如 `Asia/Shanghai`）
- [ ] `updater.schedule` 已确认（当前默认每天 `03:00`）
- [ ] `updater.timeZone`：留空表示跟随 `env.TZ`，需要独立时区再显式设置
- [ ] `kubectl.image.repository/tag/pullPolicy` 已确认（默认 `docker.io/bitnami/kubectl:latest`）
- [ ] 若使用敏感 env，已配置 `envFromSecret.name` 与 `envFromSecret.keys`

## 3) 模板与语法检查（本地）

在 `charts-src/new-api` 下执行：

```powershell
helm lint .
helm template smoke-default .
helm template smoke-updater . --set updater.enabled=true
```

如使用多域名样例：

```powershell
helm lint . -f values-multihost-tls.yaml
helm template smoke-multihost . -f values-multihost-tls.yaml
```

## 4) 安装前 dry-run（强烈建议）

```powershell
helm upgrade --install new-api . -n default --create-namespace --dry-run --debug
```

如果使用自定义 values：

```powershell
helm upgrade --install new-api . -n default -f values-multihost-tls.yaml --dry-run --debug
```

## 5) 实际安装后健康检查

```powershell
helm upgrade --install new-api . -n default --create-namespace
kubectl -n default get deploy,po,svc
kubectl -n default rollout status deploy/new-api --timeout=300s
kubectl -n default get cronjob new-api-updater
```

若开启了 updater，建议再看最近任务：

```powershell
kubectl -n default get jobs --sort-by=.metadata.creationTimestamp
kubectl -n default logs job/<latest-updater-job-name>
```

## 6) 失败回滚演练（建议在变更窗口前执行一次）

查看历史版本：

```powershell
helm -n default history new-api
```

回滚到上一个版本：

```powershell
helm -n default rollback new-api 1
kubectl -n default rollout status deploy/new-api --timeout=300s
```

说明：`updater` 任务内已实现“更新失败自动 `rollout undo`”。这里的 Helm 回滚用于发布级别问题恢复。

## 7) 常见问题速查

- `ImagePullBackOff`：检查镜像仓库连通性、镜像 tag、拉取凭据
- `updater` 任务失败：优先看 Job 日志与 RBAC 权限
- 调度时间不对：检查 `updater.timeZone` 与 `env.TZ` 的最终渲染值
