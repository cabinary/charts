# New API Helm Chart

本 chart 的集群语义参考 [New API 官方集群部署文档](https://www.newapi.ai/zh/docs/installation/deployment-methods/cluster-deployment)。

## 工作负载模式

应用实例统一使用 StatefulSet：

| 模式 | 资源 | 节点类型 |
| --- | --- | --- |
| 单机（默认） | `new-api` | `NODE_TYPE=master` |
| 主从集群 | `new-api-master`、`new-api-slave` | `NODE_TYPE=master`、`NODE_TYPE=slave` |

集群模式固定一个 master，通过 `cluster.slave.replicas` 扩展 slave。`new-api`
Service 同时选择两类应用 Pod；Kubernetes Service 对 endpoint 等权转发，因此默认流量比例约为
`1:cluster.slave.replicas`。`new-api-headless` Service 为 StatefulSet 提供稳定网络标识。

## 集群前置条件

- 所有节点连接同一个稳定、可写的 PostgreSQL 入口。
- 当前单个 Helm release 使用一个共享 Redis 兼容端点，应用不直接配置 Redis Cluster 或 Sentinel 节点列表。
- 所有节点使用相同的 `SESSION_SECRET`；由于该 release 共享 Redis，也必须使用相同的 `CRYPTO_SECRET`。
- `cluster.master.replicas` 必须为 `1`，`cluster.slave.replicas` 至少为 `1`。

建议先创建应用 Secret，再使用示例 values：

```powershell
kubectl create namespace new-api

kubectl -n new-api create secret generic new-api-cluster `
  --from-literal=SESSION_SECRET='<strong-random-session-secret>' `
  --from-literal=CRYPTO_SECRET='<strong-random-crypto-secret>'

helm upgrade --install new-api ./charts-src/new-api `
  --namespace new-api `
  -f ./charts-src/new-api/values-cluster.yaml
```

数据库与 Redis 密码 Secret 的名称和 key 见 `values-cluster.yaml`。集群 values 缺少共享
数据库或两个应用密钥时，模板会直接失败，避免生成部分可用的集群。

## 更新顺序

官方建议先更新 master，确认数据库迁移和运行状态稳定后再更新 slave。启用 `updater.enabled`
后，CronJob 会按 `new-api-master` 到 `new-api-slave` 的顺序执行滚动更新；master 失败时回滚
master 并退出，不再更新 slave。

updater 对每个 StatefulSet 的处理流程：

1. 记录该 StatefulSet 中 Ready Pod 正在运行的镜像 digest，作为回滚目标。
2. 用一次 patch 同时刷新 `restartedAt` 注解并把镜像恢复为 `image.repository:image.tag`（清除上次
   回滚钉住的 digest），然后等待至多 `updater.rolloutTimeoutSeconds`。
3. 超时后把模板钉回步骤 1 的 digest（找不到 Ready Pod 时退回 `kubectl rollout undo`），并删除仍未
   Ready 的 Pod。StatefulSet 不会主动替换一个从未 Ready 的 Pod，必须删除它，控制器才会用回退后
   的模板重建，这也是 Kubernetes 文档中 StatefulSet「Forced Rollback」的步骤。
4. 再次等待 rollout 完成，然后以失败状态退出，便于 Job 失败告警。

使用 `latest` 时只能回滚到「上一次实际运行的 digest」，无法回滚到指定版本号，生产环境建议固定
`image.tag`。Job 总超时 `updater.activeDeadlineSeconds` 默认按 StatefulSet 数量自动计算，避免回滚
阶段被 Job 超时打断。

直接通过 `helm upgrade` 修改镜像或 Pod 模板时，Kubernetes 可能同时开始两个 StatefulSet 的
滚动更新。此类生产变更应安排维护窗口；使用 `latest` 且仅需拉取新镜像时，优先使用 updater
执行顺序重启。

## 告警

`monitoring.prometheusRule.enabled=true` 会创建 PrometheusRule（需要 Prometheus Operator 的 CRD，
ACK 的 ARMS Prometheus 已内置），包含以下规则：

| 告警 | 触发条件 |
| --- | --- |
| `NewApiStatefulSetNotReady` | Ready 副本数低于期望值持续 `notReadyFor`（默认 15m） |
| `NewApiPodCrashLooping` | 单个应用 Pod 1 小时内重启超过 `restartThreshold`（默认 5）次 |
| `NewApiUpdaterJobFailed` | updater Job 失败（仅 `updater.enabled=true` 时渲染） |

集群模式下 slave 仍能承接流量，master 停摆不会体现在对外可用性上，但只有 master 执行的后台任务
（订阅额度重置、数据看板等）会停止，建议至少开启第一条规则。若 Operator 通过 `ruleSelector`
按 label 选择规则，用 `monitoring.prometheusRule.labels` 补充。

## 从 0.3.0 升级

0.3.1 为 updater 的 Role 新增 `controllerrevisions` 读权限和 `pods` 删除权限；此前
`rollout undo` 会因缺少前者而失败。`updater.activeDeadlineSeconds` 改为默认自动计算
（集群模式 1320 秒），显式设置过该值的 values 不受影响。

## 从 0.2.x 升级

0.3.0 将应用资源从 Deployment 改为 StatefulSet。升级会删除旧 Deployment 并创建新的
StatefulSet；Service selector 也新增 `component=application`。应预留短暂切换窗口，并确认新
StatefulSet Ready 后再继续其他变更。原有静态 PVC 名称保持为 `new-api`，无需改名。

集群模式下如启用 `mountLogs`，多个 Pod 需要共享可写存储。使用 chart 创建 PVC 时，
`persistence.accessModes` 必须包含 `ReadWriteMany`；使用 `existingClaim` 时，应确保该 PVC
本身支持 RWX。
