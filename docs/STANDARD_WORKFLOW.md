# iOS 标准交付工作流

每批功能、修复与视觉迁移按以下顺序完成。以根目录 `AGENTS.md` 为项目约束，安卓行为以同层 `../lolita` 当前源码为依据。

## 1. 确认范围与基线

- 修改前执行 `git status --short --branch`，检查当前分支、已有改动与最近提交，保留已有工作。
- 列出本批入口、业务结果、历史数据及图片影响；同时考虑新增、编辑、取消、保存失败与恢复。
- 检查 SwiftPM、Xcode、备份和迁移接入；不要为新增文件重生成全部 Xcode UUID。

## 2. 保留旧数据与图片

- 在独立模拟器中用虚构资料或测试数据副本验证旧版覆盖升级，不能通过卸载重装规避迁移问题，不能向来源容器写入测试资料。
- 更新前保留一致的 SQLite 备份（使用 SQLite backup API，不能在运行时只复制主数据库文件）、图片文件及偏好副本，记录原表字段和关联、图片 SHA-256。
- 迁移只做必要追加和已定义修复；本次操作没有明确授权改变的历史业务字段、时间戳、付款、关联和图片必须保留。沙盒路径变化按解析后文件及图片摘要比较。
- 取消编辑只清理本轮新增且无引用的图片；已提交图片经过 `ImageFileHelper.deleteUnreferenced` 检查后才能清理。

## 3. 实现并完成构建、回归

在项目根目录运行：

```sh
xcodebuild -project Lolita.xcodeproj -scheme Lolita -sdk iphonesimulator -configuration Debug -derivedDataPath .build/derivedData -disableAutomaticPackageResolution -skipPackageUpdates CODE_SIGNING_ALLOWED=NO build
swift test --skip-update
```

检查实际退出码、测试失败和编译诊断。数据库、事务、迁移、备份与图片安全使用有意义的回归覆盖；新增字段／实体同步导出、预览、恢复。修复失败后补跑受影响检查，记录最终通过结果；只有文档变化且已有源码验证仍有效时，不重复整套交互测试。

## 4. 模拟器实际交互与截图复核

构建通过和 macOS 组件预览不算交互验收。按本批范围运行对应原生脚本：

| 范围 | 命令 |
| --- | --- |
| 订单与账本 | `bash scripts/simulator/run_ledger_ui.sh` |
| 财务、退款与预算 | `bash scripts/simulator/run_finance_ui.sh` |
| 付款年历、月份展开与年历背景 | `bash scripts/simulator/run_calendar_ui.sh` |
| 物品登记与分层收纳 | `bash scripts/simulator/run_wardrobe_ui.sh` |
| 导入会话与商品资料 | `bash scripts/simulator/run_import_ui.sh` |
| 整套搭配、分享与日常体验 | `bash scripts/simulator/run_look_ui.sh` |
| 皮肤背景、图标与视觉 | `bash scripts/simulator/run_skin_ui.sh` |
| 预置列表、房间插图、品牌 Logo 与收纳示意图 | `bash scripts/simulator/run_builtin_ui.sh` |

- 当前脚本需要 iPhone 17 Pro / iOS 26.5 runtime，并使用 `Lolita-Ledger-UI` scheme 的 XCUITest。范围交叉时补测受影响路径，不必无差别重跑所有历史批次。
- 第五批和视觉脚本支持 `LOLITA_LOOK_V8_CONTAINER` / `LOLITA_SKIN_V8_CONTAINER` 指向已有测试模拟器的 v8 容器作为只读复制来源。视觉脚本默认读取 `.build/import-ui-work/app-data-path`；首次运行须先准备第四批测试资料，或显式指定测试容器。不能指定用户真实资料。
- 预置资料脚本分别创建全新和旧版升级两台设备，升级轮使用系统深色与辅助大字。`LOLITA_BUILTIN_V8_CONTAINER` 指定只读测试来源，`LOLITA_BUILTIN_BASELINE_APP` 指定补齐预置资料前的模拟签名应用；本机默认取第四批测试容器及上一轮视觉签名产物，其他机器须显式准备这些输入。新增预置资料时检查一次性补缺、同名自定义图保留、用户删除／移除后重启不复原、选择示意图取消／保存，以及 ZIP 恢复后的原图片。
- 历史批次脚本通过 `wait_for_builtin.py` 等待初始化落盘后再核对／准备资料；固定测试 ID 与新增房间错开。旧列逐字段核对允许新增预置元数据，但仅当旧图片为空且新文件与明确的内置原图字节一致时才接受补图；自定义图仍严格比较。视觉专项先正常初始化后恢复测试副本，不能用它替代预置专项的首次安装／升级测试。单轮补测可用 `LOLITA_BUILTIN_MODE=fresh` 或 `upgrade`，最终交付仍需有两轮通过及数据核对记录。
- 付款年历脚本用 `LOLITA_CALENDAR_V8_CONTAINER` 指定只读测试副本，默认取本机预置资料升级轮。验证四列月份、同页展开／收起、切年、实付／应付日期、真实部分付款和冷启动、长按五秒背景操作、照片选择器、共享原图清理保护、金额隐藏、七套皮肤明暗及辅助大字。写入测试偏好时先关闭独立设备，避免 cfprefsd 缓存覆盖；不通过给应用添加测试开关绕过正常流程。
- 实际操作入口、搜索／筛选、详情、新增／编辑、保存／取消、错误恢复和冷启动；按范围打开真实照片／文件选择器、键盘、原生菜单和分享面板。
- 视觉变更检查七套皮肤的系统明暗模式、系统辅助字号、底部内容遮挡、金额完整显示、页签可达、菜单文字、图标方向／语义和实际点击；启动图标要从系统桌面点击验证。查看导出的真实截图，不能仅凭自动断言宣称视觉通过。
- 原生测试需模拟签名：`CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGNING_ALLOWED=YES`，先 `build-for-testing`，再 `test-without-building`。标准无签名构建会覆盖同一 derivedData 下的产物，后续交互测试须重新生成签名产物或使用已保留的签名应用。
- 保留 `.xcresult`、日志、截图与模拟器 ID；保留失败诊断和补测记录，不能把含失败的旧包整体称为通过。脚本结束关闭本次独立设备并保留数据。
- 保存／删除后先等待完成并离开编辑／详情页，再杀进程验证冷启动；不能在确认按钮点击后立即重启。虚拟列表中元素未出现不能证明记录已删除，须结合独立 SQLite 核对；原生断言全通过但数据核对失败仍属失败。

## 5. 数据核对与体验设备更新

- 交互完成后，逐字段比较原记录，核对原关联和所有旧图片摘要，执行 `PRAGMA integrity_check` 与 `PRAGMA foreign_key_check`；新增测试记录与本批明确修改单独说明。
- 如本批涉及备份，检查 JSON／ZIP 导出、预览与恢复后的字段、关联和图片；失败恢复不得留下部分写入。
- 需要交付模拟器体验时，先备份体验设备数据库、图片与偏好，再覆盖安装经过验证的签名应用，重新核对原资料；保留原体验设备和资料。启动应用并打开 Simulator，明确哪台设备可体验。

## 6. 更新记录并提交、推送

- 在 `ANDROID_PARITY_REVIEW.md` 更新本批最终范围、构建和回归结果、模拟器实际交互、旧数据／图片核对、复现命令和验证边界。`.build/` 内的结果包、用户资料、日志和测试应用不提交；源码、必要资源、脚本与结果摘要提交。
- `git diff --check` 后审阅暂存区，确认只包含任务授权范围。提交说明覆盖最终实现及验证，不遗漏前面已完成但尚未提交的相关批次。
- 用户已要求提交和推送时，当轮执行至远端核验，不再停在“可以提交”。先 `git fetch origin` 检查分支关系，再提交并推送对应分支；有远端新增提交先安全整合，不能强制覆盖远端。网络或认证失败时保留本地提交并明确报告阻塞。
- 推送完成后检查 `git status --short --branch`，并用 `git ls-remote origin refs/heads/<分支>` 对比本地 `git rev-parse HEAD`。只有远端提交号一致才能报告已推送。
- 最终回复明确提交号与远端分支、验证结果、旧数据／图片是否保留。未做的真机、尺寸／系统版本矩阵、线上读取或通知实际送达必须如实说明，不能用其他测试替代。

## 本次已验证基线（2026-10-25）

第 4、5 批及静态视觉补齐已完成。视觉批次标准构建通过，SwiftPM 227 项回归通过；视觉最终选取的原生执行记录共 8 项通过、0 失败，覆盖七套明暗、搜索、菜单、照片选择器、辅助字号及桌面启动。独立模拟器 26 表 210 条原记录、7 个旧图片文件，以及体验模拟器 252 条记录、10 个图片文件核对保留，外键与完整性正常。

随后预置资料补齐的最终标准构建与 235 项回归通过；全新安装／旧版覆盖升级各 3 项原生交互通过，保留 26 张截图。独立升级与体验设备仍分别保留 210／252 条原记录、7／10 张原图；仅为原本空白的一个品牌 Logo 补图，原偏好保留。结果在 `.build/builtin-ui-20261025-114002/validation-report.html` 与 `validation-summary.json`，日志为 `.build/builtin-build-final.log`、`.build/builtin-tests-final.log`。原生脚本和独立 SQLite 核对均通过，未重跑全部历史批次 UI，未做真机／全部尺寸和系统验收。

本地证据位于 `.build/skin-ui-20261025-092410/validation-report.html` 和同目录 `validation-summary.json`，构建与回归日志为 `.build/visual-build-final.log`、`.build/visual-tests-final.log`。这些是本次本机证据，不是仓库自带产物；其他机器需按上述步骤重跑。未做真机、全部尺寸和系统版本验收，安卓粒子及转场动效不属于本轮静态视觉范围。

付款年历对齐已通过标准构建与 240 项回归、最终 6 项原生交互，查看 27 张截图，覆盖七套皮肤明暗及系统辅助大字。独立设备保留 451 条原记录和 30 张旧图，体验设备保留 490 条原记录、21 张旧图及原偏好；证据位于 `.build/calendar-ui-20261025-133538/validation-report.html`、`validation-summary.json`。首次偏好缓存夹具失败及驱动中断后的续跑已在报告中分别记录，最终以逐项 xcresult 与独立数据核对为准。
