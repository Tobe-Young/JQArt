# AA 已验证发布文件列表

此目录属于 Arts Git 子仓库，不是游戏资源包。修改清单前先同步 Arts；发布后仅提交此目录及其必要 meta，不要顺带提交字体/材质生成改动。

路径格式：`<bucket>/<完整 OSS prefix>.json`，例如 `jqsj-beijing/Unity/release/v04/Android.json`、`iOS.json`。v04/v05、Android/iOS 独立记录，不能混用。

清单由主项目 `Tools/AAUploadOnly.ps1`／`.sh` 调用同一个 Python 3.9+ 核心自动维护。不要手工将构建列表改成“已上传”。上传和回读全部成功、catalog 激活成功后才原子保存；失败时保留旧列表。

## 字段

- `target`：精确 OSS 目标；不记录凭据或本地绝对路径。
- `files`：以构建源相对路径为索引。
- `filename`／`objectKey`：原文件名／实际发布相对 key，冲突时为 `reconciled/<完整SHA256>/<文件名>`。
- `size`、`fileCrc32`、`md5`、`sha256`：对真实上传文件字节计算的校验值。CRC32 用 8 位十六进制文本保存。
- `catalogCrc`：Unity catalog 的 bundle CRC，十进制无符号整数。**不是 fileCrc32，二者不能比较或替换**；独立文件上传没有 catalog 时为 null。
- `bundleHash`／`cacheHash`：构建提供的 Hash／实际发布的客户端缓存 Hash。
- `remote`：回读时的 ETag、长度、Last-Modified、VersionId 和 OSS CRC64（若服务返回）。这些是对象身份，OSS CRC64 也不是 Unity CRC。
- `catalogs`：成功激活的 catalog JSON/hash 指纹及远端身份。

只有本地内容和已验证远端身份均匹配才能跳过。远端删除、改写、记录缺失时重新核验；multipart ETag 不当成整体 MD5。403、超时等会中止，不当成文件不存在。

## 使用

需要已有 ossutil 配置；可通过 `OSSUTIL_BIN`、`CONFIG_FILE`、`ENDPOINT`、`REGION`、`PYTHON_BIN` 指定，不将配置文件放进本目录。

Windows：

```powershell
powershell -NoProfile -File .\Tools\AAUploadOnly.ps1 'ServerData\ReleaseV4\Android' 'oss://jqsj-beijing/Unity/release/v04/Android/'
```

Mac：

```sh
bash Tools/AAUploadOnly.sh ServerData/ReleaseV4/iOS oss://jqsj-beijing/Unity/release/v04/iOS/
```

必须显式提供正确前缀。保留了旧入口各自的默认值，但 catalog URL 与目标不一致时会拒绝上传。

只读核验/初始化：在相同命令末尾加 `--audit-only`。该模式仅下载、校验并写本地列表，不向 OSS 上传。需要使用已发布的 catalog/hash；若本地构建 catalog 与现网不同，先将现网两文件下载至 Artifacts，再用 `--catalog <Artifacts中的catalog.json>` 指定，同时仍以真实构建目录提供 bundle。

已映射的嵌套 bundle 使用此清单的 `objectKey → 原始相对路径` 关联定位构建源文件，因此复核前也必须同步清单。未知 catalog 结构或编码 bundle URL 会在上传前停止，不能将漏识别的依赖当成已经验证。

不要并行发布同一前缀。工具有本地锁、清单乐观检查和远端 catalog 漂移检查，但 **不是跨机器分布式事务**；Git 同步清单和一次只运行一个发布者仍是要求。

JSON 与 hash 是两个 OSS 对象，无法保证读者完全看不到中间态。工具先回读资源，再备份旧清单、写 JSON、最后写 hash。失败证据及原始 catalog 保存在主项目 `Artifacts/AAUploads/`，不能将中途失败当作整套已发布，也不会自动删除旧 bundle 或清客户端缓存。
