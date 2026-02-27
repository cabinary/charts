# charts
Repository for collecting personal Helm charts

## 打包（避免 Windows CRLF / `^M`）

`helm package` 会直接打包当前工作区文件；如果文件在 Windows 中是 CRLF，产物里也会带 `^M`。

仓库提供了 LF-safe 打包脚本：

```powershell
pwsh ./scripts/package-helm-chart.ps1 -ChartPath charts-src/new-api -Destination docs -UpdateIndex
```

说明：

- 脚本默认从工作区复制 chart 到临时目录，并在打包前统一转换为 LF。
- 因此发布产物不受本地工作区 CRLF 影响，同时支持未提交改动参与打包。
- `-UpdateIndex` 会同步更新 `docs/index.yaml`。
- 发布版本一律增量追加：保留 `docs/` 中历史 `.tgz`，只新增新版本并合并 `index.yaml`，不要删除旧版本包。

如需强制按提交内容打包（忽略工作区未提交改动）：

```powershell
pwsh ./scripts/package-helm-chart.ps1 -ChartPath charts-src/new-api -Destination docs -UpdateIndex -SourceMode GitHead
```

## 统一增量发布脚本（适用于所有 chart）

仓库提供通用发布脚本（默认按 patch 递增版本并打包）：

```powershell
pwsh ./scripts/release-helm-chart.ps1 -Project charts-src/new-api
```

也支持只传项目名（会自动解析到 `charts-src/<name>`）：

```powershell
pwsh ./scripts/release-helm-chart.ps1 -Project new-api
```

常用参数：

- `-Project`：项目名或路径（推荐相对路径）
- `-Bump patch|minor|major|none`：版本增量策略（默认 `patch`）
- `-Version x.y.z`：显式指定版本（优先级高于 `-Bump`）
- `-SourceMode WorkingTree|GitHead`：打包来源（默认 `WorkingTree`）
- `-NoUpdateIndex`：不更新 `docs/index.yaml`
- `-DryRun`：只解析/预览，不改文件

给 AI 的约定：当需要发布当前编辑项目时，始终显式传入 `-Project`（优先用相对路径，如 `charts-src/new-api`），保证是增量发布，不删除历史 `.tgz`。

## 一键校验 tgz 是否含 `^M`

默认校验 `docs` 下所有 `.tgz`：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-helm-tgz-line-endings.ps1
```

仅校验单个包：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-helm-tgz-line-endings.ps1 -PackagePath .\docs\new-api-0.1.1.tgz
```

脚本在检测到 `^M` 时会返回非零退出码，可直接用于 CI。

## new-api 的 Ingress / Istio VirtualService

`charts-src/new-api` 已支持通过 values 配置 `Ingress` 与 `VirtualService`，但不包含 Ingress Controller 或 Istio Gateway 资源本体定义。

安装前建议先执行清单：`docs/new-api-preflight-checklist.md`

- `Ingress` 通过 `ingress.className` 指定对应 ingress class。
- `VirtualService` 通过 `istio.virtualService.gateways` 指定外部已存在的 gateway（例如 `istio-system/panda-wiki-gateway`）。
- 两者默认共用 `route.hosts` 与 `route.paths`，并支持各自 `hosts` 覆盖，确保配置对称可控。
- `Ingress` 的 TLS 为数组 `ingress.tls[]`（为空时回退复用 `route.tls[]`）。

示例：

```yaml
route:
	hosts:
		- "codex.example.com"
		- "claude.example.com"
		- "gemini.example.com"
	tls:
		- secretName: "example-tls"
		  hosts:
			  - "codex.example.com"
			  - "claude.example.com"
			  - "gemini.example.com"
	paths:
		- path: /
			pathType: Prefix
			matchType: prefix

ingress:
	enabled: true
	className: "alb"
	hosts: [] # 为空时回退 route.hosts
	tls: [] # 为空时回退 route.tls
	annotations: {}

istio:
	enabled: true
	virtualService:
		apiVersion: networking.istio.io/v1
		gateways:
			- istio-system/panda-wiki-gateway
		# 可选：显式覆盖 hosts，默认回退为 route.hosts
		hosts: []
		# 可选：显式覆盖 http，默认由 route.paths 自动生成
		http: []
```
