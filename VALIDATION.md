# 验证记录

验证日期：2026-10-25（上海时区）。

## 编译与运行

- 工具链：Xcode 27.1 / Swift 6.4，项目采用 Swift 5 语言模式。
- iOS 最低部署版本：17.0。
- iOS Simulator Debug 构建成功，已安装并启动应用。
- 界面测试设备：iPhone 18 Pro，iOS 27.0 模拟器。
- 工程文件已通过 `plutil -lint` 检查。
- 图标为 1024 × 1024 RGB PNG，无透明通道。

## 核心测试

`swift test`：9 项测试全部通过，0 失败。

1. 自然季度边界及排除区间终点，避免重复统计。
2. 周一开始的跨年周计算。
3. 闰年二月的每日分桶及总时长 / 总距离配速。
4. 零时长、极短时长、非法距离、未来日期和极端历史日期拒绝入库。
5. JSON 备份往返与重复 UUID 拒绝。
6. 本周尚未跑步时的连续周数。
7. 周日起始、跨年季度切换及全年 12 个月分桶。
8. 未填写距离的记录计入次数、时长，但不参与配速；空数据不产生配速。
9. 未支持的备份版本和无效设置拒绝。

## 真实界面测试

`RunningLogUITests.testAddEditAndPersistence`：1 项通过，0 失败。

验证内容：从记录页新建 → 填写距离和中文备注 → 保存 → 点击卡片中部进入编辑 → 修改备注 → 保存 → 终止进程 → 重新启动并读取相同修改 → 切换概览 → 滑动删除并确认 → 等待删除动画结束后确认记录消失。

测试中发现并修复了普通按钮样式导致卡片留白无法点击的问题，回归测试已覆盖。测试会清理其专用标记的记录，截图中的跑步是自动测试数据。

截图：

- [概览](Screenshots/dashboard.png)
- [记录列表](Screenshots/records.png)
- [编辑表单](Screenshots/editor.png)

本次完整界面测试结果：`/tmp/RunningLogUIRegression.xcresult`。

可在 Xcode 使用 Product → Test 重跑界面测试。核心测试通过独立 Swift Package 运行。

## 验证范围

尚未进行真机签名安装、App Store 发布、iOS 17 实机运行、iPad 界面验收及系统文件选择器导入导出的端到端测试。备份数据结构和校验已通过核心测试；导入导出仍建议在目标真机试用。

## 1.1 iCloud 同步增量验证（2026-10-25）

- iOS Debug 应用及界面测试目标编译成功；Info.plist 中的容器、团队、签名状态均已检查实际构建产物，不只检查工程文本。
- `swift test`：**21 项通过，0 失败**，其中保留原有 9 项，新增 12 项同步测试。
- 新增测试覆盖独立设备新增合并、较新编辑获胜、删除防复活、同时间确定性排序、幂等性、交换性、结合性、无效远端数据拒绝、旧备份迁移、同步账号及墓碑持久化、可见记录一致性、同版本异常冲突、时钟回拨及异常元数据。
- iPhone 18 Pro / iOS 27.0 界面回归：**2 项通过，0 失败**。
  - 新增 → 整卡点击编辑 → 保存 → 进程重启 → 修改仍保留 → 确认删除。
  - 开启 iCloud → 显示未配置提示 → 关闭 → 重启 → 开关状态仍为关闭。
- Debug 界面测试显式设置 `RUNNINGLOG_DISABLE_CLOUD_FOR_TESTS=1`，禁止真实 CloudKit 请求，避免将测试记录传到设备登录的真实账号。该环境开关只在 Debug 生效。
- 工程、Info.plist 和 entitlements 均通过 `plutil -lint`，源文件通过 `git diff --check`。
- 完整界面测试结果：`/tmp/RunningLogCloudUIFinal.xcresult`。
- [iCloud 设置页截图](Screenshots/icloud-settings.png)展示的是未配置签名时的提示，不代表已经上传成功。

真实 iCloud 上传/下载、多设备联网冲突、账号切换、配额限制和 Production Schema 部署尚未实测；须配置属于用户的开发者团队与容器，并按 [ICLOUD_SETUP.md](ICLOUD_SETUP.md) 的双设备流程验收。现有自动化测试不能替代真实云端验收。

## 应用图标验证（2026-10-25）

- 修复此前几乎全黑的图标，使用内置 ImageGen 生成青绿色跑道与荧光绿跑者图标。
- 最终资源：`RunningLog/Assets.xcassets/AppIcon.appiconset/AppIcon-Running.png`。
- 检查实际 PNG：1024 × 1024、无 Alpha 通道；未预绘制外部圆角。
- 图标资源目录编译成功（`BUILD SUCCEEDED`），无图标资源警告。
- 已目视检查实际打包的 `AppIcon60x60@2x.png`（120 × 120），确认跑者与跑道显示正常，不再是黑色图片。
- 本次仅新增图像资源及转换脚本，不涉及业务逻辑，未重复执行业务测试。
