# SwiftUI 源码组件预览

运行 `./scripts/preview/export.sh`，在 `.build/layout-previews/` 生成 100 张 PNG：衣橱、统计、编辑、付款日历、主题五组组件，覆盖七种皮肤的明暗模式，默认皮肤另有 320/430 pt 宽度和辅助字号布局分支。
使用项目真实的列表行、颜色选择、已选服饰、统计图表、日期格和主题卡片，以示例数据直接通过 SwiftUI `ImageRenderer` 渲染。
不读取桌面或 Simulator 窗口，不读取业务数据库。

这能检查组件间距、颜色、卡片和长文字布局；macOS 上运行不能代表 iOS 的系统导航栏、安全区、List、Form 等系统控件，也不是当前屏幕截图。macOS 的系统文字样式不会随该环境值按 iOS 方式放大，因此 `large-text` 图片仅检查辅助字号触发的布局分支，不能作为 iOS 大字体适配验收。
脚本暂时将导出器接入 SwiftPM 测试运行器，退出时清理，不改变正式测试集合或应用入口。

Apple API 限制：https://developer.apple.com/documentation/swiftui/imagerenderer
