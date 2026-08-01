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
后，CronJob 会按 `new-api-master` 到 `new-api-slave` 的顺序执行滚动更新；任一 StatefulSet
失败时会回滚该 StatefulSet 并停止后续更新。

直接通过 `helm upgrade` 修改镜像或 Pod 模板时，Kubernetes 可能同时开始两个 StatefulSet 的
滚动更新。此类生产变更应安排维护窗口；使用 `latest` 且仅需拉取新镜像时，优先使用 updater
执行顺序重启。

## 从 0.2.x 升级

0.3.0 将应用资源从 Deployment 改为 StatefulSet。升级会删除旧 Deployment 并创建新的
StatefulSet；Service selector 也新增 `component=application`。应预留短暂切换窗口，并确认新
StatefulSet Ready 后再继续其他变更。原有静态 PVC 名称保持为 `new-api`，无需改名。

集群模式下如启用 `mountLogs`，多个 Pod 需要共享可写存储。使用 chart 创建 PVC 时，
`persistence.accessModes` 必须包含 `ReadWriteMany`；使用 `existingClaim` 时，应确保该 PVC
本身支持 RWX。
