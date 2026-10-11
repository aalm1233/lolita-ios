# iOS 对照 Android 当前功能审计（2026-10-11）

基准为同层 `/Users/dengtong/code/lolita` 的当前可达源码和 Manifest，不采用旧 README 的五底栏、图鉴或共享库描述。本文件已更新为本轮修改后的状态；早期修复经过见 [修复记录](/Users/dengtong/code/lolita-ios/docs/IOS_FIXES_2026-10-10.md)。

“已实现”表示入口和业务逻辑已接入并通过相应编译或数据回归，不代表真实页面点击、真机或视觉验收完成。iOS 不要求照搬 Compose 控件，但需保持业务结果。

## 后续功能已接入

| 优先级 | 功能 | 当前 iOS 状态 | Android 当前依据 |
| --- | --- | --- | --- |
| 高 | 正式 ZIP 备份、ZIP 恢复 | 设置中可导出/导入 ZIP，支持安卓旧 ZIP、JSON、图片预览与事务替换恢复；图片校验、暂存和失败重试已接入。 | `ui/screen/settings/BackupRestoreScreen.kt`、`data/file/BackupManager.kt` |
| 高 | 淘宝订单 Excel 导入 | 多文件 XLSX 解析、订单选择和去重、编辑补图、定金尾款自动/手工配对、余额日期及单事务保存；去重键独立持久保存。 | 设置有正式入口，`ui/screen/settings/TaobaoImportViewModel.kt` |
| 高 | 付款通知及提前天数 | 编辑页支持提醒与提前 0–365 天；付款变化自动同步，已付/删除/关闭提醒后取消；通知可跳转付款编辑。 | `ui/screen/price/PaymentEditScreen.kt`、`data/repository/PaymentRepository.kt`、`data/notification/PaymentReminderScheduler.kt` |
| 高 | 系统日历联动 | 设置开启 EventKit 同步，为开启提醒的未付日程创建/更新事件；已付/删除/关闭同步后清理本应用事件。权限失败不阻断付款保存。 | `data/notification/CalendarEventHelper.kt` |
| 中 | 每日穿搭提醒 | 可设置时间，按当地日历滚动注册未来十四天；当天记录后取消提醒，启动/前台续期，点击进入今日记录。 | `ui/screen/settings/SettingsScreen.kt`、`data/notification/DailyOutfitReminderReceiver.kt` |
| 中 | 桌面穿搭小组件 | 新 WidgetKit extension，小/中尺寸展示今日状态和件数；App Group 共享快照、跨午夜刷新、点击进入今日记录。扩展编译及共享数据验证通过，未验收桌面展示。 | `AndroidManifest.xml`、`ui/widget/OutfitWidget.kt`、`res/xml/outfit_widget_info.xml` |
| 中 | 付款年历自定义背景 | 年/月历共用背景，支持相册、相机、预览及恢复默认；图片纳入引用保护和沙盒路径迁移。 | `ui/screen/calendar/PaymentCalendarScreen.kt` |

## 已有基础但仍需继续对齐

| 范围 | 已完成 | 仍有差异 |
| --- | --- | --- |
| 数据导出 | 全实体和图片 JSON/ZIP；预览、明确替换确认及单事务恢复；十二表分段 CSV | 含当前不支持的共享/图鉴实体数据的备份明确拒绝恢复，避免静默丢失；CSV 是导出格式。 |
| 图片交互 | 详情按图片比例展示；整组全屏翻页、缩放；画廊点图全屏横滑，下方可进详情；品牌 Logo/缺图字首 | 共享图片 Hero 转场仍未完整对齐。 |
| 主题与导航 | 七套皮肤、皮肤字体、渐变导航栏和底栏配色；四底栏/首页四栏，下方列表横滑切页；首页单行搜索按钮/四页签/操作，点击搜索替换为输入框和取消，新增在右下角 | 仍使用 SF Symbols 和原生 TabView，安卓皮肤专属图标、毛玻璃及入场动效尚未完整对齐；手势需实际交互验收。 |
| 统计交互 | 五页签、环图与趋势；点图表切片/柱/趋势下钻；心愿实现率；分布和趋势类型切换；按年补零 | 安卓当前页面主要使用环图/折线，iOS 新增图表类型切换；实际图表触控尚未验收。 |
| 金额显示偏好 | 衣橱、筛选合计、套装、统计图表/明细和个人汇总统一设置；隐藏后保留件数及百分比 | 付款/价格编辑和服饰详情保留业务金额供核对，不能将这些入口一概认定为安卓全局隐藏偏好的缺失。 |
| 付款编辑 | 全款/定尾款、自动日程、保留已付历史；月历可编辑/标已付，管理列表侧滑直接标已付 | 系统通知/日历权限与真实交互仍需设备验收。 |

提醒存在系统调度边界：付款只注册最近 48 条，穿搭注册未来十四天，每次启动、前台或数据变化会重新同步。连续十四天以上不打开应用时，穿搭提醒不会无限续期；与安卓后台接收器实现有差异。真机小组件还需要开发者团队为两个 target 配置 `group.com.lolita.ios` 的签名权限。

## 本轮已补齐的入口与行为

| 功能 | 修改后状态 | iOS 源码入口 |
| --- | --- | --- |
| 主导航 | 首页 / 穿搭 / 统计 / 个人；愿望单归入首页第四栏 | [LolitaNavHost](/Users/dengtong/code/lolita-ios/Sources/UI/Navigation/LolitaNavHost.swift) |
| 衣橱呈现 | 默认两列大图，可切列表、两列、三列、画廊；卡片展示状态、属性、价格和品牌 Logo；长按可编辑/确认删除，列表区横滑切四栏 | [ItemListScreen](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Item/ItemListScreen.swift)、[共享卡片](/Users/dengtong/code/lolita-ios/Sources/UI/Component/LolitaCollectionComponents.swift) |
| 组合筛选与排序 | 品牌、分类、服装/小物组、待尾款、季节、风格、颜色；多季节拆逗号匹配；更新时间、价格、名称双向排序；筛选合计 | [ItemListViewModel](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Item/ItemListViewModel.swift) |
| 季节和颜色编辑 | 季节可多选，旧“春,秋”可以正常展示编辑；自定义颜色可添加、显示和移除 | [ItemEditScreen](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Item/ItemEditScreen.swift) |
| 服饰详情 | 大图、标题状态、品牌分类/季节颜色等属性；尺码表、所属套装/位置跳转；价格与已付/待付摘要；删除确认 | [ItemDetailScreen](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Item/ItemDetailScreen.swift) |
| 套装列表和详情 | 关联缩略图、件数及总价；真实可达删除；详情直接选衣增减、拖动排序、价格/已付/未付汇总；提交单事务 | [CoordinateDetailScreen](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Coordinate/CoordinateDetailScreen.swift)、[CoordinateRepository](/Users/dengtong/code/lolita-ios/Sources/Data/Repository/CoordinateRepository.swift) |
| 位置收纳 | 图片卡与“未分配”入口；详情批量放入/移出；未分配服饰批量指定位置；整个批次回滚保护 | [LocationDetailScreen](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Location/LocationDetailScreen.swift)、[LocationDetailViewModel](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Location/LocationDetailViewModel.swift) |
| 心愿 | 优先级图片卡、筛选/金额；新增编辑确认删除 | [WishlistScreen](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Wishlist/WishlistScreen.swift) |
| 穿搭日志 | 照片、日期角标、照片/服饰数量；标题/计数/按钮合为紧凑顶栏，点击展开搜索日记、日期和关联服饰；新增任意日期、多图编辑、确认删除 | [OutfitLogListScreen](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Outfit/OutfitLogListScreen.swift)、[OutfitLogEditViewModel](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Outfit/OutfitLogEditViewModel.swift) |
| 今日快速记录 | 首页常驻入口；加载并更新当天备注、照片和选择；空选择验证；事务内再次查当天，避免重复插入；跨午夜不移动昨天记录 | [QuickOutfitLogViewModel](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Outfit/QuickOutfitLogViewModel.swift)、[OutfitLogRepository](/Users/dengtong/code/lolita-ios/Sources/Data/Repository/OutfitLogRepository.swift) |
| 穿搭详情 | 关联服饰照片卡可跳详情并直接移除关联；保留服饰、照片和笔记 | [OutfitLogDetailScreen](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Outfit/OutfitLogDetailScreen.swift) |
| 推荐搭配 | 独立分类分组页；排除目标同分类组；合并套装与穿搭共现的 1.3 加权；全候选排序后展示分类 | [RecommendationRepository](/Users/dengtong/code/lolita-ios/Sources/Data/Repository/RecommendationRepository.swift)、ItemDetailScreen 内 ItemRecommendationScreen |
| 统计和付款年历 | 五个完整名称页签；点击明细进服饰列表；月/季度趋势可选年份并补齐 12 月/4 季；年历已付/待付/逾期汇总；月历编辑付款和标已付 | [StatsPageScreen](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Stats/StatsPageScreen.swift)、[PaymentCalendarScreen](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Payment/PaymentCalendarScreen.swift) |
| 个人页 | 紧凑顶栏；头像、昵称、服饰/套装汇总和消费合成较矮资料卡；属性管理整合六类入口；总价显示设置 | [SettingsScreen](/Users/dengtong/code/lolita-ios/Sources/UI/Screen/Settings/SettingsScreen.swift) |
| 图片查看 | 自然宽高比、照片计数、整组全屏分页、缩放和拖动 | [ImageGalleryPager](/Users/dengtong/code/lolita-ios/Sources/UI/Component/ImageGalleryPager.swift)、[FullScreenImageViewer](/Users/dengtong/code/lolita-ios/Sources/UI/Component/FullScreenImageViewer.swift) |

## 本轮发现并修复的 BUG

1. 多季节服饰在重命名/删除季节时遗漏：Repository 和实际属性管理共用逐个 token 更新，并在同事务保存。删除“春”保留“秋”，不会误改“春季”。
2. 价格编辑在等待数据库读取期间重新读取可变类型，可能把全款写成零定尾款：采用提交快照、保存期禁用表单；价格已删除时抛错保留输入。
3. 普通穿搭无法创建任意日期记录：补新建分支，后续保存更新同一 ID；新选择限制已拥有服饰，历史关联可保留/移除。
4. 快速穿搭每次新增一条：改为当地日范围内加载与事务 upsert；跨午夜按新的一天保存，不修改昨日日期；重复打开空记录页不产生重复当天日志。
5. 位置删除提前删图：移除提前清理，沿用 Repository 数据提交后检查引用。
6. 空字符串风格分布与下钻不一致：两边统一归入“未分类”。
7. 头像导入后不清选择对象，同一图片无法重试：成功/失败/离页清理选择，使用请求 UUID 防止旧任务覆盖新选择。
8. 本轮所有新增 GRDB 观察工厂均在非 UI 隔离范围创建，抓取闭包显式 @Sendable，避免先前资料管理 actor 闪退再次出现。
9. 导入订单去重若依赖描述，编辑服饰会使去重失效：新增 v4 可空订单键迁移并在普通编辑保留，备份和 CSV 同步导出。
10. ZIP 恢复失败不能销毁预览和临时图片：失败保留供重试，取消/成功才清理；异常在可见 sheet 中显示。
11. 通知/小组件冷启动链接可能在数据库初始化时丢失：根视图先收取 URL，初始化完成后消费导航；通知委托安全切回 MainActor 访问 Repository。
12. 小组件文件写入失败不能阻止关闭穿搭提醒：文件和通知错误分开处理，关闭时先取消并等待旧调度任务，再独立移除已有请求。
13. EventKit 提前天数以固定秒数相减会跨夏令时偏移一小时：通知与日历共用 Calendar 减天，日历使用绝对报警日期。

统计口径继续跟随当前安卓：总消费仅计 OWNED；月度已付消费按 dueDate 的 UTC 月归类而非 paidDate；多季节服饰完整价格分别计入每个季节，因此季节累计可能重复，界面已说明。iOS 愿望单件数继续使用 DISTINCT，避免照搬安卓多价格导致重复计数的缺陷。

## 不应误列为缺失功能

- Android 当前底部导航是四项；旧五项/图鉴说明不作为依据。
- 共享同步 API/Repository/实体虽存在，但当前无消费者或可达页面，不列为对齐欠账。
- Android 多图编辑的 reorderImages 只存在 VM，未接真实控件；本轮不将其列为 iOS 少实现的可用行为。
- 小组件在 Android Manifest 中已注册，确实可达；本轮已补 WidgetKit，不能只根据旧 README 判断。
- 当前安卓没有可达的分布图表类型切换入口；iOS 已新增此选项，早期将其列作安卓现成功能不准确。

## 验证

- SwiftPM 完整 **112 项测试通过**；在此前 69 项基础上增加 43 项，覆盖 ZIP/CSV/恢复回滚与真实安卓备份、XLSX/配对/去重、通知与日历同步、跨日/DST、统计筛选、金额偏好、背景图片保护和普通编辑保留导入键。
- Xcode iOS Simulator Debug 最终构建通过，包含已嵌入的 WidgetKit extension；模拟签名下 App Group 容器可访问。正常日志中的 AppIntents 元数据提示与编译错误无关；没有新增 actor 隔离警告。
- iOS 26.5 命令行 harness 链接真实 Xcode dylib：五种资料的观察/改名/删除/取消、衣橱与统计新观察、今日穿搭 upsert、“未分配”详情均通过；只使用内存数据库。
- 最新源码组件预览生成 200 张，覆盖十种页面组合（含穿搭与展开搜索）、七套皮肤的明暗模式、默认皮肤 320/393/430 pt 与辅助字号布局分支。图片为空的示例占位，不读取模拟器窗口；macOS ImageRenderer 不支持部分原生交互控件和真实 iOS 动态字体，不能代替实际页面验收。
- 已在同一 iPhone 17 Pro / iOS 26.5 Simulator 更新安装并启动；业务表逐行对比导入后备份一致（新增可空订单键除外），140 件服饰、27 套搭配、144 条付款、3 条日志/6 关联等均保留，190 张图片逐张 SHA-256 校验通过；数据库完整性 ok，外键错误 0。
- App Group 的 `outfit-widget.json` 已写入，与三条实际日志及 4/1/1 件关联计数一致；这验证共享数据通路，不等于桌面小组件显示/点击验收。
- 相册/相机/文件选择器、通知授权及实际投递、EventKit 授权及系统日历显示未做真实页面点击或真机验收；未绕过此前拒绝的屏幕访问权限。
- 未读取模拟器屏幕或做真实页面点击/真机验收；没有发布、提交 Git 或修改 Android 源码。
