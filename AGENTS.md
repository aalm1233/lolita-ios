# iOS 项目协作约定

- SwiftUI + GRDB，最低 iOS 17 / macOS 14；手动依赖注入通过 `AppModule`。
- Android 行为基准在同层 `../lolita`，以当前源码为准；其 README 和部分测试脚本仍含旧图鉴功能描述。
- 开始修改前先看 `git status --short`，保留用户已有改动。UI 文案使用中文。

## 构建与回归

```sh
xcodebuild -project Lolita.xcodeproj -scheme Lolita -sdk iphonesimulator -configuration Debug -derivedDataPath .build/derivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
swift test --skip-update
```

- `Tests/` 使用 SwiftPM 测试 target 验证数据库、付款、迁移、备份和图片安全；不需要连接真机。
- Android Debug 构建可使用 Android Studio 自带 JDK：
  `JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ./gradlew assembleDebug`。
- 模拟器构建通过不等于真机或交互验收通过；报告验证边界。
- 组件视觉检查可运行 `scripts/preview/export.sh`，输出到 `.build/layout-previews/`；使用示例数据直接渲染，不读取应用窗口。该 macOS 预览不能验收 iOS 系统控件或实际动态字体缩放。

## 数据约束

- 自增实体采用 `MutablePersistableRecord`。Swift 属性 `id = 0` 仅代表尚未插入，`encode(to:)` 必须写 NULL，`didInsert` 回填真实 ID。
- 数据库迁移必须保留历史数据与关联；`v3-payment-status` 修复历史 ID 0 和待尾款状态。
- Repository 的不可变存储只有 GRDB `DatabaseQueue`，采用 `Sendable`；不要以 `nonisolated(unsafe)` 绕过并发检查。
- 付款/价格变化和派生服饰状态在同一数据库事务内更新；不覆盖愿望单状态。
- 价格页面通过 `saveWithPayments` 生成付款日程；编辑时保留已付历史，只重建剩余未付金额。
- 套装关联保存和穿搭关联保存必须为单一事务；删除套装先解除服饰关联。
- 风格、季节、渠道的重命名/删除需要同时更新服饰字符串引用。

## 图片与备份

- 图片统一走 `ImageFileHelper`；原图在数据库保存成功后才能清理，取消编辑只清理本次新增文件。
- 已提交图片清理通过 `deleteUnreferenced` 检查所有引用；只能删除应用图片目录内的文件。
- 安装更新后沙盒 UUID 可能变化；启动时事务重定位已有图片字段，旧路径只能映射到当前图片目录内实际存在的普通文件。共享引用按解析后的文件路径比较，保留业务字段和时间戳。
- `StringList` 数据库存储和 JSON 备份都是字符串数组，兼容旧 `{ "values": [...] }` 编码。
- `BackupManager` 包含 JSON（内嵌图片）、服饰 CSV、安卓旧 JSON 默认字段兼容、预览和事务恢复。
- 新字段/实体需要同步备份导出、预览、恢复和回归测试。
- 恢复前在 UI 展示预览并明确替换当前数据；设备日历事件 ID、提醒注册状态不能跨设备直接复用。

## 页面与观察

- 新增和编辑成套考虑；服饰页四栏为位置/服饰/套装/心愿，底部穿搭进入日志。
- 长期观察 Task 必须取消或由 `.task(id:)` 管理；禁止在每次 onAppear 累积订阅。
- GRDB 6 的 `ValueObservation.tracking` 抓取闭包应在非隔离 Repository/工厂中创建，并显式标记 `@Sendable`；不要在 `@MainActor` 方法内让普通闭包继承 UI 隔离。ViewModel 在主 actor 消费观察结果。
- 日历时间范围使用 `[月初, 下月月初)`，月份切换需取消旧观察。
- 保存失败保留页面与输入；使用 `userFacingError` 显示可理解的提示，不向用户展示 SQL。
- 复用 `lolitaNavBar`、`LolitaCard`、`LolitaSection` 和皮肤系统；编辑返回要考虑未保存更改。
- 新增 Swift 文件必须同时接入 SwiftPM 与 Xcode 项目文件。当前 Xcode 项目为 JSON 格式，避免为添加文件重生成全部 UUID。
