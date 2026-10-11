# iOS 对照 Android 审查（2026-10-10）

本文件保留最初审查结论。后续修复状态见 [iOS 修复记录](docs/IOS_FIXES_2026-10-10.md)，当前已通过编译及 19 项回归测试；下表描述的是修复前的问题。

基准：当前 `../lolita` 源代码，非仅 README。此次为代码审查，未修改业务实现。iOS 使用 SwiftUI + GRDB，Android 使用 Compose + Room。平台 API 不要求逐字照搬，但页面入口、数据约束和业务结果应一致。

## 优先修复的 BUG

| 优先级 | 问题及触发条件 | 代码位置 | 修复方向 |
| --- | --- | --- | --- |
| P0 | 所有自增实体默认 `id = 0`，GRDB 会把 0 当实际主键写入；同表第二次新增冲突。首次预设品牌循环第二条即失败，事务回滚，初始化错误又被忽略。Room 的 `autoGenerate` 对 0 的处理不能直接移植。 | `Sources/Data/Database/Entity/Brand.swift:5`、其他自增实体；`Sources/AppModule.swift:75`；`Sources/LolitaApp.swift:17` | 新记录主键编码为 NULL/省略主键，统一处理自动生成 ID；测试全新数据库初始化、连续新增及关联记录。 |
| P1 | 实体采用 `PersistableRecord`，却提供 `mutating didInsert`；GRDB 6.29.3 的该协议要求非 mutating 回调，默认实现为空，不能依赖当前回调回填 ID。即使修正主键写入，返回记录仍可能带旧 ID。 | `Sources/Data/Database/Entity/Item.swift:4`、`:33`；`Price.swift`、`Payment.swift` 等 | 改为 `MutablePersistableRecord` 并使用可变记录插入，或显式返回插入生成的 ID；验证后续外键关联。 |
| P1 | “穿搭”底栏打开套装列表，穿搭日志列表只定义未挂到任何入口，快速穿搭也随之不可达。 | `Sources/UI/Navigation/LolitaNavHost.swift:43`；`Sources/UI/Screen/Outfit/OutfitLogListScreen.swift` | 按安卓接入穿搭日志导航，保留服饰页内套装入口。 |
| P1 | 服饰、套装、位置无新增入口；编辑 ViewModel 只读取并更新已有 ID，传 0 也不会创建。新用户无法完成核心录入。 | `Sources/UI/Screen/Item/ItemListScreen.swift`、`ItemEditViewModel.swift:75`；`CoordinateEditViewModel.swift:56`；`LocationEditViewModel.swift:27` | 新增/编辑两种模式，新增时调用 insert，并补列表新增按钮。 |
| P1 | 保存使用 `try? await save()` 后无条件 dismiss；数据库冲突或写入失败仍关闭页面，输入丢失且不显示错误。 | `Sources/UI/Screen/Item/ItemEditScreen.swift:120`；套装、位置、穿搭、价格、付款编辑页 | 仅保存成功关闭，失败保留输入并显示可操作错误。 |
| P1 | 位置图片替换/移除时立即删除原文件；随后取消编辑或保存失败，数据库仍指向已删除图片。 | `Sources/UI/Screen/Location/LocationEditViewModel.swift:35`、`:42` | 原图保存成功后清理；取消只清理本次新增图片。 |
| P1 | 月份查询结束时间是最后一天 00:00，最后一天其余时间的付款被漏掉。 | `Sources/UI/Screen/Payment/PaymentCalendarViewModel.swift:27` | 使用 `[月初, 下月月初)` 查询，而不是最后一天午夜的 BETWEEN。 |
| P1 | 切换月份不断创建永久观察 Task，旧月份订阅未取消；后续数据库变化会让旧订阅重新写入当前月份的数据。其他列表/统计的 onAppear 也重复创建观察任务。 | `Sources/UI/Screen/Payment/PaymentCalendarViewModel.swift:30`；`StatsPageViewModel.swift:20`；`ItemListViewModel.swift:21` | 保存 Task，切换/销毁时取消，或用 SwiftUI `.task(id:)` 管理观察生命周期。 |
| P1 | 付款增改删不联动服饰待尾款状态；已付完仍可为 PENDING_BALANCE，有未付尾款却仍为 OWNED。主服饰列表又只显示 OWNED，手动设待尾款后消失。 | `Sources/Data/Repository/PaymentRepository.swift`；`Sources/UI/Screen/Item/ItemListScreen.swift:58` | 对齐 Android 的未付尾款计数规则，在事务中刷新状态并提供待尾款入口。 |
| P2 | 价格/付款非法金额被转为 0，负数也可保存；定金、尾款和总价之间无归一化。 | `Sources/UI/Screen/Payment/PriceEditViewModel.swift:32`；`PaymentEditViewModel.swift:35` | 保存前校验数值与金额关系，对齐安卓 `normalizePrice`。 |
| P2 | 愿望单优先级件数因 LEFT JOIN 多条价格而重复计数：1 件服饰有 2 条价格时显示 2 件。Android 当前 SQL 也有相同问题，不应照搬。 | `Sources/Data/Repository/PriceRepository.swift` 的 `getWishlistByPriorityStats`；安卓 `PriceDao.kt:153` | 使用 `COUNT(DISTINCT i.id)` 或先聚合每件服饰价格。 |
| P2 | 删除风格/季节/来源仅删属性表，服饰仍保留旧名称；重命名也未级联更新。安卓在事务内更新/清空引用。 | `Sources/Data/Repository/StyleRepository.swift`、`SeasonRepository.swift`、`SourceRepository.swift` | 同事务更新所有字符串引用，并提供重命名入口。 |
| P2 | 删除服饰、套装、穿搭日志没有清理图片，长期累积孤立文件；编辑页取消新增图片也没有清理。 | 对应 Repository 的 delete；各编辑 ViewModel | 写入成功后清理不再引用的文件；明确图片所有权，避免误删共享图片。 |
| P2 | 多个页面调用 `showBack: true` 却不传 onBack，自绘返回按钮点击无效果。 | `Sources/UI/Component/LolitaNavigationBar.swift:23`；`PriceManageScreen.swift:46` 等 | 默认调用环境 dismiss，或要求调用端提供返回闭包。 |

## 对照安卓仍缺少的实现

| 范围 | iOS 当前状态 / 缺失 |
| --- | --- |
| 页面结构 | 安卓当前服饰页是“位置 / 服饰 / 套装 / 心愿”；iOS 是“位置 / 服饰 / 套装 / 图鉴”，且图鉴重复显示 OWNED。安卓 README 仍写独立图鉴，但当前代码未发现对应图鉴页面，应以当前导航为准。 |
| 服饰管理 | 缺搜索、组合筛选、排序、视图切换、颜色编辑、购买渠道、尺码表图片、套装归属和顺序管理；详情和操作也未完整对齐。 |
| 套装管理 | 缺增删关联服饰、排序、套装价格汇总；编辑目前只改名称/描述/图片。 |
| 穿搭 | 日志入口未接；普通编辑缺关联服饰选择；快速记录插入日志和关联服饰分两次事务，失败可留下不完整日志。 |
| 属性设置 | 只有品牌/分类/风格/季节新增删除及主题选择；缺位置管理列表、渠道管理、属性整合管理和重命名。 |
| 数据迁移 | 无 JSON 备份恢复、预览、CSV 导出、安卓备份兼容导入；无淘宝 Excel 导入与导入引导。 |
| 提醒及系统集成 | 无付款通知调度、日历事件同步、每日穿搭提醒、桌面小组件及快速记录外部入口。iOS 应分别用 UserNotifications、EventKit、WidgetKit 等实现对应结果。 |
| 共享库 | 安卓已有 `SharedLibrarySyncApi`、Repository、同步状态及 Remote 实体；iOS 无对应数据模型和同步流程。 |
| 统计 | 目前是一页文字/金额列表；缺安卓五页签、付款年历、季节消费维度、季度趋势、图表及统计下钻；缺套装数量等总览信息。 |
| 推荐 | 有基础引擎和详情推荐列表，但缺安卓独立推荐页面、交互与完整属性录入，颜色向量目前无法通过服饰编辑页设置。 |
| 视觉交互 | 已有 7 套皮肤和基础卡片/图片组件，但页面大量使用系统 List/Form/SF Symbols；未对齐安卓皮肤专属图标、动效、Hero、筛选控件和未保存变更保护。 |

## 验证及边界

- 初始 iOS Git 工作区干净。没有改动业务源码。
- 使用内存 SQLite 复现：第一次显式插入主键 0 成功，第二次报 `UNIQUE constraint failed: brands.id`。
- 使用内存 SQLite 复现：1 件服饰关联 2 条价格时，当前优先级 SQL 得到件数 2。
- 已检查实际使用的 GRDB 6.29.3 源码：`PersistableRecord.didInsert` 非 mutating，默认实现为空；官方源码建议需要可变回调时采用 `MutablePersistableRecord`。
- Xcode 构建在依赖解析/检出阶段长时间没有进展，已中止；未得到编译通过或源码编译失败结论。上述为代码审查及 SQL 验证，不代表完成真机交互测试。当前未发现项目测试目录，Package.swift 未配置测试 target。
- 月度消费按 dueDate 而非 paidDate 归属、总消费只计 OWNED 等口径在安卓当前 SQL 中也存在；应先统一业务定义，不能直接归为 iOS 移植差异。

## 建议实施顺序

1. 主键/ID 回填、初始化错误处理，确保全新安装可正常启动并连续新增。
2. 服饰/套装/位置新增、穿搭导航、保存失败保护与图片安全。
3. 付款状态联动、日历时间边界/订阅取消、金额校验。
4. 属性级联、备份恢复与安卓数据导入，保护已有数据。
5. 搜索筛选、套装关联、完整统计、共享同步、系统提醒与视觉交互。
