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

如需强制按提交内容打包（忽略工作区未提交改动）：

```powershell
pwsh ./scripts/package-helm-chart.ps1 -ChartPath charts-src/new-api -Destination docs -UpdateIndex -SourceMode GitHead
```

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
