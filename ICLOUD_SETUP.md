# iCloud 同步配置与验收

本项目使用 CloudKit **私有数据库**保存跑步记录，用户不需要注册应用账号。数据属于设备当前登录的 iCloud 账号，不会显示为 iCloud Drive 中的 JSON 文件；如需文件备份，仍可在设置页导出 JSON 并保存到 iCloud Drive。

## Xcode 配置

1. 打开 `RunningLog.xcodeproj`，选择 TARGETS → RunningLog → Signing & Capabilities。
2. 选择支持 iCloud 能力的 Apple 开发者团队，启用 Automatically manage signing。将 `com.example.RunningLog` 改为自己唯一的 Bundle Identifier。
3. 检查已加入的 iCloud 能力，勾选 CloudKit，在容器列表选择或创建属于该团队的容器，例如 `iCloud.com.dailiang.RunningLog`。
4. 在 Build Settings 搜索 `RUNNINGLOG_ICLOUD_CONTAINER`，将 Debug 和 Release 都设为上一步实际创建的容器 ID。默认值为 `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`。
5. 检查 `RunningLog/RunningLog.entitlements` 中的容器与该设置一致。如果 Xcode 自动改成了固定值，确保固定值与 Build Settings 一致。不要仅在代码中修改容器名称。
6. 运行已签名的 Debug 应用。在 iPhone 系统设置登录 iCloud，打开应用 → 设置 → iCloud 同步。
7. 等状态显示“已同步至 iCloud”后再验证另一台设备。

工程通过 `RunningLog/Info.plist` 把团队、容器和签名构建设置传给同步服务；未选择团队或以 `CODE_SIGNING_ALLOWED=NO` 构建时，只显示配置提示，不访问 CloudKit。模拟器本地开发仍可继续使用记录和 JSON 备份功能。

参考：[Apple 启用 CloudKit 指南](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app)、[Xcode 管理 iCloud 容器](https://help.apple.com/xcode/mac/current/en.lproj/devcae40ccb9.html)。

## 数据模型与环境

- 数据库：Private Database。
- 自定义区域：`RunningLogRecords`。
- 记录类型：`RunEntryV1`。
- 自定义字段：`payload`，类型为 Bytes，内容是带修订信息的 JSON。
- 不依赖 Query 查询，因此不需要配置查询索引。
- Debug 使用 Development，Release 使用 Production；这是两个隔离的数据环境，测试设备必须使用相同环境和容器。

首次在开发环境成功同步后，检查 CloudKit Console 中的 `RunEntryV1` 和 `payload` 字段。发布 TestFlight / App Store 前，需将开发 Schema 部署到 Production。只部署结构，不会将开发环境的用户记录搬到生产环境。发布前请在生产环境完成一轮真机验收。

参考：[Apple 容器与环境说明](https://developer.apple.com/documentation/cloudkit/ckcontainer)、[部署容器 Schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)。

## 同步行为

- 默认关闭，由用户在设置页开启。开启前的本机记录会合并到云端，不会以空设备覆盖云端。
- 本机先保存，新增、修改、删除后延迟约 1 秒触发同步；应用进入前台时同步，并在前台每分钟拉取其他设备的更改。
- 也可点击“立即同步”。应用退到后台后不保证继续执行，不包含后台推送或实时同步。
- 关闭同步仅停止自动上传与下载，不删除本机或云端数据。
- 同步范围是跑步记录；每周目标、周起始日和外观设置保留在各自设备。
- 同编号冲突按编辑时间选择较新的整条记录；时间相同按修订号排序，确保多设备收敛。请保持设备系统时间准确。
- 删除使用带版本的墓碑记录；暂不清理墓碑，避免长时间离线的设备将旧记录重新上传。
- 账号切换后暂停同步，不会把原账号的本地记录自动传到另一个账号。切回原账号可继续；需要跨账号迁移时请导出 JSON，在新账号的全新安装中导入。
- 断网、空间不足或服务限流时，本机记录继续保存；错误显示在设置页。限流不立即循环重试，可稍后手动同步或等待前台下一轮。
- 同步过程中继续编辑的内容会进入下一轮；遇到服务器版本冲突会重新拉取、合并，最多立即重试三轮。

数据同步会传播删除，不能代替独立备份。建议保留定期导出的 JSON。卸载前先检查“已同步至 iCloud”及最近同步时间；未同步的数据仍可能只在本机。

## 双设备验收

1. 两台设备使用同一个 iCloud 账号、同一个容器、同一个 Development / Production 环境。
2. A 开启同步，等待成功；B 开启同步，检查 A 原有记录是否出现。
3. A 新增一次跑步；B 点击立即同步，核对日期、时长、距离、感受、备注和统计。
4. B 修改记录；A 同步，检查修改是否保留，次数不会重复增加。
5. A 断网，B 删除该记录并完成同步；A 恢复联网并同步，确认旧记录不会复活。
6. 两机离线各自新增不同记录，联网后两边同步，确认两条均保留。
7. 关闭同步后添加记录，再开启同步，确认离线修改也能上传。
8. 验证未登录、断网、空间不足时仍可新增本机记录，并能在恢复后重试。

自动化测试覆盖本地合并、删除墓碑、旧版迁移和未配置签名的降级提示；真实账号上传下载、配额与多设备网络冲突仍需以上述步骤验收。本次开发环境没有配置你的开发者团队，不能将本地测试结果当作真实 iCloud 同步成功。
