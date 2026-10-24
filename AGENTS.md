# iOS 项目协作约定

- SwiftUI + GRDB，最低 iOS 17 / macOS 14；手动依赖注入通过 `AppModule`。
- Android 行为基准在同层 `../lolita`，以当前源码为准；其 README 和部分测试脚本仍含旧图鉴功能描述。
- 开始修改前先看 `git status --short`，保留用户已有改动。UI 文案使用中文。

## 构建与回归

```sh
xcodebuild -project Lolita.xcodeproj -scheme Lolita -sdk iphonesimulator -configuration Debug -derivedDataPath .build/derivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
swift test --skip-update
```

- 原生交互回归运行 `bash scripts/simulator/run_ledger_ui.sh`（需要 iOS 26.5 模拟器 runtime）。脚本创建独立设备，从 `788fb8d` 旧版真实覆盖升级，使用虚构资料，核对旧库与原图，再通过 `Lolita-Ledger-UI` scheme 的 XCUITest 点击实际页面；结果与截图保存在 `.build/ledger-ui-*/`。退出仅关闭本次设备，保留其数据供检查。
- `UITests/` 同时接入 SwiftPM 和 Xcode，但用 `#if os(iOS)` 限定；macOS 的 `swift test` 不执行这些原生交互，必须以模拟器 `.xcresult` 与独立 SQLite 核对结果为准。深色与辅助字号通过模拟器系统 `appearance` / `content_size` 设置验证，不以源码预览替代。

- `Tests/` 使用 SwiftPM 测试 target 验证数据库、付款、迁移、备份和图片安全；不需要连接真机。
- Android Debug 构建可使用 Android Studio 自带 JDK：
  `JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ./gradlew assembleDebug`。
- 模拟器构建通过不等于真机或交互验收通过；报告验证边界。
- 组件视觉检查可运行 `scripts/preview/export.sh`，输出到 `.build/layout-previews/`；使用示例数据直接渲染，不读取应用窗口。该 macOS 预览不能验收 iOS 系统控件或实际动态字体缩放。

- 第2批原生回归：`bash scripts/simulator/run_finance_ui.sh`，覆盖旧版升级、参考价不建单与主动采用草稿、重启恢复输入、退款超限及到账、共价取消与再购买、月预算／年度明细、隐私、大字体与真实键盘；结果在 `.build/finance-ui-*/`。

- 第3批原生回归：`bash scripts/simulator/run_wardrobe_ui.sh`，独立设备从旧版覆盖升级，真实照片选择器与多图封面、尺码规格、退出／重启草稿、柜架层格新增、拥有状态限制、整树跨房间移动及草稿关联、分类重命名、位置删除保留物品、系统深色辅助大字和真实键盘。结果在 `.build/wardrobe-ui-*/`。

## 数据约束

- 自增实体采用 `MutablePersistableRecord`。Swift 属性 `id = 0` 仅代表尚未插入，`encode(to:)` 必须写 NULL，`didInsert` 回填真实 ID。
- 数据库迁移必须保留历史数据与关联；`v3-payment-status` 修复历史 ID 0 和待尾款状态，`v4-import-order-keys` 保存淘宝订单去重键。普通服饰编辑不得清除 `importOrderKeys`。
- `v7-wardrobe-storage` 仅为物品追加组合、原文规格、多张详情图、收纳节点字段，为分类追加稳定品类，新增 `storageNodes` / `itemDrafts` 两表；保留旧单图、位置、业务字段和时间戳。历史迁移只读取当时已有的列，不能依赖未来实体字段。
- 分类显示名与 `categorySemantic` 分开；仅迁移时对明确旧名称回填一次，重命名不得重新猜品类。规格按稳定品类展示，切换品类保留其他规格，所有单位和范围按原文保存。
- 收纳为房间 → 柜架 → 层格，禁止循环、跨房间父节点及同级重名；移动整树须在同一事务更新下级节点、物品房间及草稿。新收纳只允许已拥有物品，旧未拥有物品的历史位置可保留或移除。收纳选择页按节点 ID 隔离勾选状态，读取完成前禁用提交，切换节点不能复用上一位置的勾选。删除有内容的位置须明确确认，只清除位置，不能删除物品或账本。
- 物品草稿独立保存图片引用，自动保存且可显式退出／恢复；还原全部输入需清理过时草稿。成功保存物品与删除对应草稿在同一事务内完成，编辑按原 `updatedAt` 拒绝过期草稿覆盖。提交先捕获规格、图片、封面和收纳快照；取消仅清理本轮新增且已无引用的文件。
- Repository 的不可变存储只有 GRDB `DatabaseQueue`，采用 `Sendable`；不要以 `nonisolated(unsafe)` 绕过并发检查。
- 付款/价格变化和派生服饰状态在同一数据库事务内更新；不覆盖愿望单状态。
- `v6-after-sale-budget` 仅追加独立参考价、到账退款、取消约定和月预算四表，保持十四张原表字段与关联不变。退款以稳定操作 ID 防重、指纹拒绝陈旧保存；撤销只标记原记录，不能减少实付到有效退款以下。取消解除绑定、主件和共价小物回到心愿，原订单、计划、实付和图片保留；已取消订单不可重绑或续付，再买需新订单。
- `v5-order-ledger` 追加当前订单绑定、付款阶段、主件共价和付款操作标识；迁移保留十二张旧表全部原字段（含金额、日期和时间戳），只为关系明确的历史订单建立绑定，不推断未知实付。
- 价格页面通过 `saveWithPayments` / `OrderRepository` 保存订单与阶段；新计划不创建未付 Payment。真实实付单独记录，整数分计算、操作 ID 防重和表单账本指纹核对在同一写事务完成；改阶段只解除被移除阶段的分配，不改原实付金额、日期或 ID。
- 当前绑定与原账本分开；历史已购保留拥有证据、余额未知，待核对需明确确认后跟踪。归档保留所有原记录并停止待付与提醒；共价小物只引用主件账本且跟随主件状态，不能另建价格或形成循环主件。
- 套装关联保存和穿搭关联保存必须为单一事务；删除套装先解除服饰关联。
- 风格、季节、渠道的重命名/删除需要同时更新服饰字符串引用。
- 季节为逗号分隔的多选值；重命名/删除必须按完整 token 在同事务更新，不能用 season = 单个名称遗漏组合季节。
- 今日穿搭按当地日范围 [日初, 次日日初) 查询，快速保存需在写事务内再次查当天避免重复；普通日志新增仍可选择任意日期。
- 价格表单保存使用提交快照，不在 await 后重新读取可变类型或金额；新关联穿搭服饰仅允许已拥有，历史关联可保留/移除。

## 图片与备份

- 图片统一走 `ImageFileHelper`；原图在数据库保存成功后才能清理，取消编辑只清理本次新增文件。
- 已提交图片清理通过 `deleteUnreferenced` 检查所有引用及头像/付款日历背景偏好；只能删除应用图片目录内的文件。
- 安装更新后沙盒 UUID 可能变化；启动时事务重定位已有图片字段，旧路径只能映射到当前图片目录内实际存在的普通文件。共享引用按解析后的文件路径比较，保留业务字段和时间戳。
- `StringList` 数据库存储和 JSON 备份都是字符串数组，兼容旧 `{ "values": [...] }` 编码。
- `BackupManager` 包含完整 JSON、ZIP 图片备份、二十表分段 CSV、安卓旧 ZIP/JSON 兼容、预览和事务恢复。ZIP 统一经过 `ZipArchiveReader` 校验路径、CRC 和解压大小；恢复失败保留暂存文件供重试，取消或成功后清理。
- 淘宝导入采用独立 `importOrderKeys` 去重，订单、价格、付款和派生状态在单事务内提交；订单描述不是去重键。尚未提交的照片由导入会话管理。
- 新字段/实体需要同步备份导出、预览、恢复和回归测试。`iosWardrobeVersion: 1` 必须包含收纳节点与物品草稿表，旧备份补缺省字段且不丢旧单图；JSON/ZIP/预览/恢复/二十表 CSV 同步接入。节点照片、全部详情图和草稿图片均参与备份、沙盒路径重定位和 `deleteUnreferenced` 引用保护。iOS 订单备份使用独立 `iosLedgerVersion: 2` 标识并包含订单、阶段、参考价、退款、取消与预算，兼容旧 `iosLedgerVersion: 1` 的十四表备份，不冒充安卓格式 15；无标识的旧备份恢复后走历史订单建模，标识存在但缺表必须拒绝。
- 付款日历与提醒以当前已核对订单的阶段剩余金额投影，阶段投影使用负 ID 与 `lolita://stage/` 链接；原 Payment ID 保持正数。真实消费按实付金额统计，月份仅使用已知 paidDate，未知日期不以到期日补造。
- 恢复前在 UI 展示预览并明确替换当前数据；设备日历事件 ID、提醒注册状态不能跨设备直接复用。

- 月预算以当地月范围统计，净支出＝原实付－有效到账退款；跨月退款计入到账月，可为负。以前月份未付、未定期计划和未知实付日期分别列示，不以到期日补造实际付款月份。独立零元参考价合法，不能建单或改变状态；共价小物不可保留独立参考价。
- 新记账表单持久保存输入、账本基准与操作 ID；恢复草稿不自动提交，陈旧基准拒绝保存；取消、成功才清理草稿。保存按钮与延伸到安全区的背景必须分开，避免可访问性点击命中底部空白。

## 页面与观察

- 新增和编辑成套考虑；服饰页四栏为位置/服饰/套装/心愿，底部穿搭进入日志。
- 首页顶部按当前安卓使用搜索按钮/四页签/操作单行；搜索展开后整行替换为输入框和取消，取消清空关键词。新增按钮在右下角，首页列表/网格滚动内容需保留底部空间，避免遮挡末项。
- 穿搭和个人根页面使用 `LolitaRootToolbar`，统计直接以紧凑页签为顶栏，根页面隐藏原生导航栏，避免重复占高；详情仍用可见 `lolitaNavBar` 保留返回。穿搭计数并入顶栏，搜索按按钮展开。
- 长期观察 Task 必须取消或由 `.task(id:)` 管理；禁止在每次 onAppear 累积订阅。
- GRDB 6 的 `ValueObservation.tracking` 抓取闭包应在非隔离 Repository/工厂中创建，并显式标记 `@Sendable`；不要在 `@MainActor` 方法内让普通闭包继承 UI 隔离。ViewModel 在主 actor 消费观察结果。
- 日历时间范围使用 `[月初, 下月月初)`，月份切换需取消旧观察。
- 保存失败保留页面与输入；使用 `userFacingError` 显示可理解的提示，不向用户展示 SQL。
- 复用 `lolitaNavBar`、`LolitaCard`、`LolitaSection` 和皮肤系统；编辑返回要考虑未保存更改。
- 新增 Swift 文件必须同时接入 SwiftPM 与 Xcode 项目文件。当前 Xcode 项目为 JSON 格式，避免为添加文件重生成全部 UUID。

## 通知与小组件

- 付款提醒和每日穿搭提醒分别使用 `lolita.payment.` / `lolita.outfit.` 前缀，只取消自己管理的请求；日期提前天数按 Calendar 减天，避免固定秒数的 DST 偏移。
- 付款通知最多注册最近 48 条；穿搭提醒滚动注册未来十四天，启动/前台续期。权限失败应解释原因，不能阻止业务数据保存。
- EventKit 只更新或移除带本应用 URL 标识的事件，设备事件映射保存在本机偏好中，不复用安卓 ID。
- App 与 WidgetKit 共用 `OutfitWidgetShared.swift`、`group.com.lolita.ios`；共享文件失败不能阻断提醒取消。模拟器验证使用带模拟签名的构建，真机需团队签名配置 App Group。
- URL 入口位于永久根视图，数据库准备好后再消费导航，避免冷启动丢失通知/小组件链接。
