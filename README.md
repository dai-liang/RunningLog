# 跑步手记

使用 SwiftUI + Swift Charts + CloudKit 开发的原生 iOS 应用（1.1），最低支持 iOS 17，兼容 iPhone 和 iPad。界面与代码注释均为中文，无第三方依赖。

## 已实现

- 新增、编辑、删除跑步记录，默认当前日期与时间，可补记历史记录。
- 时长精确到秒；距离选填，支持跑步感受与备注；自动计算配速。
- 按周、月、季度、年统计次数、时间、距离与平均配速，支持前后切换统计区间。
- 分布图可切换时长、次数、距离；周/月按天、季度/年按月显示。
- 每周次数与时长目标、连续跑步周数。
- 按月归档、按本月/今年筛选、按备注或感受搜索。
- 设置每周起始日、浅色/深色/跟随系统外观。
- JSON 备份导入与导出，按编号合并并确认，同编号以备份为准。
- 本机原子文件持久化；读取失败保护原文件并暂停写入，避免空数据覆盖。
- 可选 iCloud 私有数据库同步，支持离线编辑、跨设备合并、删除防复活、状态显示和手动重试。

## 启动

1. 使用 Xcode 打开 `RunningLog.xcodeproj`，选择 `RunningLog` scheme。
2. 选择 iOS 17 或更高版本的模拟器，点击 Run。
3. 真机运行时，在 Signing & Capabilities 中选择自己的开发团队，并将 `com.example.RunningLog` 改为唯一的 Bundle Identifier。

本地记录不需要服务器、API Key 或联网。iCloud 同步需配置开发者团队及 CloudKit 容器，详见 [iCloud 配置与验收](ICLOUD_SETUP.md)。真机签名、TestFlight 和 App Store 发布需配置 Apple 开发者账号。

## 统计口径

- 区间包含起点、不包含终点；日期采用设备当前时区与公历。
- 默认周一为周起始日，可在设置中改为周日。
- 季度为自然季度：1–3、4–6、7–9、10–12 月。
- 一条记录计为一次，同日可以有多条记录。
- 配速 = 有距离记录的总时长 / 总距离；没有距离的记录仍计入次数、时长。
- 连续跑步周数在本周未跑时保留截至上周的连续周数；断开一个完整周则清零。
- 日期需在 1900 年至当前时间之间；时长为 1 秒至 24 小时，距离为 0–500 公里，备注最多 2000 字。

## 数据与隐私

数据及同步元数据位于应用沙箱 `Library/Application Support/RunningLog/runs.json`。默认只在本机保存；开启 iCloud 后，跑步记录（含备注）会同步到当前账号的 CloudKit 私有数据库。未接入广告、分析或自建服务器。卸载前请确认已同步或导出备份；JSON 备份不含同步账号标记和删除墓碑，共享时请注意个人备注。

当前版本不包含 GPS 轨迹、Apple 健康同步、实时计时、通知提醒或自建账号系统。iCloud 同步在前台执行，不保证后台实时同步。

## 验证

核心统计及数据校验测试独立于 iOS 运行：

```sh
swift test
```

编译模拟器版本：

```sh
xcodebuild -project RunningLog.xcodeproj -scheme RunningLog \
  -sdk iphonesimulator -configuration Debug \
  -derivedDataPath /tmp/RunningLogDerivedData CODE_SIGNING_ALLOWED=NO build
```

测试覆盖季度边界、跨年周、闰月、加权配速、无效输入、备份往返、重复编号、连续周计算，以及同步冲突、删除墓碑、旧版迁移和时钟回拨。详细验证结果见 `VALIDATION.md`。

## 界面预览

以下图片来自通过验收的 iPhone 模拟器界面测试，其中跑步记录为测试数据：

- [统计概览](Screenshots/dashboard.png)
- [跑步记录](Screenshots/records.png)
- [编辑跑步](Screenshots/editor.png)

界面测试可在 Xcode 通过 Product → Test 执行，覆盖新增、编辑、重启后读取和删除。测试会清理带有专用标记的测试记录。

1.1 新增：[iCloud 设置页预览](Screenshots/icloud-settings.png)（展示未配置签名时的提示）。请先按 [iCloud 配置指南](ICLOUD_SETUP.md) 关联自己的开发者团队与容器，再开启真实同步。
