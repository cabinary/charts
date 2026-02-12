# charts
Repository for collecting personal Helm charts

## 打包（避免 Windows CRLF / `^M`）

`helm package` 会直接打包当前工作区文件；如果文件在 Windows 中是 CRLF，产物里也会带 `^M`。

仓库提供了 LF-safe 打包脚本：

```powershell
pwsh ./scripts/package-helm-chart.ps1 -ChartPath charts-src/new-api -Destination docs -UpdateIndex
```

说明：

- 脚本会先从 `git HEAD` 导出 chart（仓库内是 LF），再执行 `helm package`。
- 因此发布产物不受本地工作区 CRLF 影响。
- `-UpdateIndex` 会同步更新 `docs/index.yaml`。
