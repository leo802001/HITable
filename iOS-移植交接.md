# HITable · iOS 移植交接文件

> 交接自：Android 工作线（已完成 1.2.0 正式版）
> 生成时间：2026-09-24
> 适用：在新工作窗口开始 iOS 端开发

---

## ⚠️ 0. 开工前必须知道的三个硬前提

### ① iOS 开发必须有 macOS + Xcode —— 这是最大的阻塞点

你的主力机是 **Windows 11**。Flutter 在 Windows 上：

| 操作 | Windows 能否做 |
| --- | --- |
| `flutter analyze` / `flutter test`（Dart 层） | ✅ 能 |
| 生成 `ios/` 工程目录 | ✅ 能（已替你生成好了） |
| `flutter build ios` / `flutter run -d <iPhone>` | ❌ **不能** |
| Xcode 配置签名 / 描述文件 / Podfile | ❌ 不能 |
| 真机调试、TestFlight 分发 | ❌ 不能 |

**可选路径（按性价比排序）：**

1. **借/用一台 Mac**（实验室、朋友、学校机房）—— 最省事，一次性把签名和真机跑通
2. **云 Mac** —— MacinCloud / MacStadium，按小时或按月租，远程桌面进去用 Xcode
3. **GitHub Actions 的 macOS runner** —— 本仓库是 **public**，Actions **免费且不限量**，
   可以配 CI 自动 `flutter build ios --no-codesign` 产出 `.app`。
   **但只能"构建"，不能"调试"** —— 真机安装仍需签名环境
4. **黑苹果 / 虚拟机** —— 不建议，不稳定且违反 Apple 条款

> **建议**：先在 Mac 上（哪怕借一天）把「签名 + 真机跑起来」这一步打通，
> 之后的日常 Dart 层开发可以回到 Windows 做（`analyze`/`test` 都能跑）。

### ② Apple Developer 账号 $99/年

| 方式 | 限制 |
| --- | --- |
| 免费个人签名 | 证书 **7 天过期**、必须 USB 连真机、最多 3 个 App、不能 TestFlight |
| 付费开发者账号 | 一年有效期、TestFlight 分发（最多 100 台设备）、可上架 App Store |

**自己用 + 给几个同学用**：免费签名够用（每 7 天重签一次）。
**要长期分发 / 上架**：必须付费账号。

### ③ 本仓库已公开 —— 证书类文件绝不能提交

`https://github.com/leo802001/HITable`（public）

**防护已经替你做好了**，现状如下：

| 敏感文件 | 由谁挡 | 状态 |
| --- | --- | --- |
| `ios/Pods/`、`ios/.symlinks/`、`xcuserdata/` | `ios/.gitignore`（`flutter create` 自动生成） | ✅ |
| `ios/Flutter/Generated.xcconfig`、`flutter_export_environment.sh`、`ephemeral/` | 同上 | ✅ |
| `ios/Runner/GeneratedPluginRegistrant.*` | 同上 | ✅ |
| `*.mobileprovision`、`*.p12`、`*.certSigningRequest` | 根 `.gitignore`（**我补的**） | ✅ |
| `android/key.properties`、`*.jks`、`PROGRESS.md` | 根 `.gitignore`（原有） | ✅ |

我实测过 `git add -An ios/` —— **没有敏感文件会被收录**。

> 另外：iOS 的描述文件和私钥更常见的落点是**用户主目录**
> （`~/Library/MobileDevice/Provisioning Profiles/` 和 `~/Library/Keychains/`），
> 本来就不在项目里，天然安全 —— 但别手贱往项目里拷。

---

## 1. 交接快照

| 项 | 值 |
| --- | --- |
| 应用名 | HITable |
| 当前版本 | **1.2.0+2017**（Android 正式版，已发 GitHub Release） |
| 包名 / Bundle ID 建议 | `com.leocy.hitable` |
| 本地工作目录 | `C:\Users\leo\Projects\hitable` |
| 远端仓库 | `https://github.com/leo802001/HITable`（public，main 分支） |
| Flutter | 3.47.4 stable |
| Dart | 3.13.3 |
| Dart SDK 约束 | `>=3.10.0 <4.0.0` |
| Android minSdk / targetSdk | 26 / 34 |
| 作者署名 | Leocy / QQ 647259208 |

### Android 侧构建命令（作为参照，别动）

```bash
export PATH="$LOCALAPPDATA/flutter/bin:$PATH"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export JAVA_HOME="C:\Program Files\Eclipse Adoptium\jdk-17.0.20.8-hotspot"

flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64 --split-per-abi \
  -P force-version-code-ignoring-abi=true
```

**Android 已验证基线**：`1.1.10 (2016)` 起用户真机确认全部功能正常；
新 Android 包 versionCode **必须 > 2017**。

---

## 2. 代码盘点：能复用什么、必须重写什么

**核心结论：Dart 层约 96%（11,100 / 11,629 行）可以直接复用，iOS 的工作量集中在原生侧。**

| 层 | 文件 | 行数 | iOS 侧命运 |
| --- | ---: | ---: | --- |
| `lib/domain/` | 6 | 1,203 | ✅ **原样复用**（纯 Dart：模型、排课引擎、周次解析） |
| `lib/application/` | 2 | 381 | ✅ 原样复用（Riverpod 状态） |
| `lib/data/` | 3 | 849 | ✅ 复用（`sqflite` 支持 iOS，仅路径不同） |
| `lib/import/` | 5 | 1,820 | ✅ 复用（纯 Dart 解析 + `webview_flutter`） |
| `lib/presentation/` | 12 | 6,243 | ✅ 基本复用；`magic_os_guide_page.dart` 需换成 iOS 版 |
| `lib/notifications/` | 3 | 595 | ⚠️ **要过一遍**（iOS 有 64 条待发通知上限，见 §5.4） |
| `lib/widget/` | 2 | 461 | 🟡 **数据契约复用，原生渲染重写** |
| `android/` Kotlin | 2 | 676 | 🔴 **全部重写**（→ Swift + WidgetKit） |
| `test/` | 22 | 4,022 | ✅ 复用（纯 Dart 测试，Windows 上就能跑） |

> **重要发现**：`lib/` 里**没有任何 `Platform.isAndroid` / `defaultTargetPlatform` 分支**。
> 平台差异全部收敛在两处：
> 1. `lib/widget/next_course_widget_service.dart` 的那一个 `MethodChannel`
> 2. 各插件自身的平台实现
>
> 这是个很好的起点 —— **Dart 层不需要为了 iOS 加平台判断**。

---

## 3. Android 专有资产清单（iOS 需要等价物）

### 3.1 Kotlin（676 行，全部要重写）

| 文件 | 作用 | iOS 对应 |
| --- | --- | --- |
| `android/app/src/main/kotlin/com/leocy/hitable/MainActivity.kt` | 接收 Dart 下发的数据，写 SharedPreferences，触发小组件刷新 | `AppDelegate.swift` + 平台通道，写入 **App Group 的 UserDefaults** |
| `android/.../NextCourseWidget.kt` | RemoteViews 渲染小组件（固定槽位、三态色条、位图圆角） | **WidgetKit（SwiftUI）**，Timeline Provider |

### 3.2 Android 资源（小组件用）

```
android/app/src/main/res/layout/next_course_widget.xml   # 4 槽位布局
android/app/src/main/res/values/colors.xml               # 浅色配色
android/app/src/main/res/values-night/colors.xml         # 深色配色
android/app/src/main/res/xml/next_course_widget_info.xml # 小组件元信息
android/app/src/main/res/drawable/widget_*.xml           # 圆角卡片
```

→ iOS 侧对应：SwiftUI View + `Color(light:dark:)` 或 asset catalog + `.widgetConfiguration`

### 3.3 AndroidManifest（5 个权限 + 3 个 receiver）

| Android | iOS 对应 |
| --- | --- |
| `POST_NOTIFICATIONS` | `UNUserNotificationCenter.requestAuthorization`（无 manifest 项） |
| `SCHEDULE_EXACT_ALARM` | **iOS 不需要** —— iOS 的通知调度很准时，没有精确闹钟概念 |
| `RECEIVE_BOOT_COMPLETED` | 不需要（iOS 无此概念） |
| `INTERNET` | 无需声明 |
| `VIBRATE` | 通知的 `.sound` / 震动随通知设置 |
| `<receiver .NextCourseWidget>` | Widget Extension target |
| `<receiver>` ×2（重启/时区恢复） | 不需要 |

### 3.4 平台专有 UI 页面

| 文件 | 现状 | iOS 处理 |
| --- | --- | --- |
| `lib/presentation/magic_os_guide_page.dart`（241 行） | 5 个国产 Android 品牌的后台设置引导 | **iOS 用不上**，需写 iOS 版「通知权限 + 后台刷新」说明，或按平台隐藏入口 |
| `lib/presentation/notification_settings_page.dart:144` | 「查看国产 Android 后台设置」入口 | 按平台切换文案 |
| `lib/presentation/tutorial_page.dart:89` | 提到「国产 Android 后台设置教程」 | 同上 |

---

## 4. 依赖逐个判定（iOS 就绪度）

```yaml
dependencies:
  android_intent_plus: ^6.1.0          # 🔴 Android 专用
  csv: ^6.0.0                          # ✅ 纯 Dart
  excel: ^4.0.6                        # ✅ 纯 Dart
  file_picker: ^13.1.0                 # ✅ 支持 iOS
  flutter_local_notifications: ^22.0.0 # ⚠️ 支持 iOS，但要配置
  flutter_riverpod: ^2.6.1             # ✅ 纯 Dart
  flutter_timezone: ^5.1.0             # ⚠️ 需实测 iOS 支持
  google_mlkit_text_recognition: ^0.16.0 # ⚠️ 支持 iOS，但要改 Podfile
  path: ^1.9.0                         # ✅ 纯 Dart
  sqflite: ^2.3.3+1                    # ✅ 支持 iOS（数据库路径不同）
  timezone: ^0.11.1                    # ✅ 纯 Dart
  webview_flutter: ^4.14.1             # ✅ 支持 iOS（WKWebView）
```

### 4.1 逐个处理说明

| 包 | iOS 侧要做的事 |
| --- | --- |
| **`android_intent_plus`** | 🔴 **必须替换**。它只在 Android 用（跳系统设置页）。iOS 无等价功能 → 要么用 `url_launcher` 跳 `App-Prefs:`（Apple 会拒审），要么直接删掉这条路径，iOS 侧不提供「跳系统设置」按钮 |
| **`flutter_local_notifications`** | ① `ios/Runner/AppDelegate.swift` 里注册插件；② 请求通知权限；③ `Info.plist` 无需额外界限；④ **注意 64 条待发上限**（见 §5.4） |
| **`google_mlkit_text_recognition`** | 在 `ios/Podfile` 里手动加中文识别包：<br>`pod 'GoogleMLKit/TextRecognitionChinese'`<br>并确认 `platform :ios, '15.5'`（ML Kit 最低要求） |
| **`flutter_timezone`** | 确认有 iOS 实现；没有就自己用 `NSTimeZone` 写个小通道（工作量很小） |
| **`sqflite`** | iOS 上 `getDatabasesPath()` 落在 App Sandbox 的 Library 目录，**代码不用改** |
| **`webview_flutter`** | iOS 用 WKWebView。**教务登录的 Cookie 行为与 Android 不同**，需重新验证「登录 → 读课表」全流程 |
| **`file_picker`** | iOS 需要在 `Info.plist` 加 `NSPhotoLibraryUsageDescription` 等隐私描述串，否则崩溃 |

---

## 5. iOS 侧待办（按依赖顺序，建议照这个顺序做）

### 5.1 工程与签名（**必须在 Mac 上做**）

`ios/` 脚手架**已经生成好了**（我在 Windows 上用 `flutter create --platforms=ios .` 生成的），
包含 `Runner.xcodeproj` / `Runner.xcworkspace` / `Info.plist` / `ios/.gitignore` 等。

> **注意**：`ios/Podfile` **不在**脚手架里 —— 这是正常的。
> Flutter 的 Podfile 由工具链在**首次构建 / pod install 时自动生成**，`flutter create` 不产出它。
> 所以别直接跑 `pod install`（没有 Podfile 会失败），走下面的顺序。

在 Mac 上：

```bash
cd hitable-ios
flutter pub get
flutter build ios --no-codesign    # 首次构建会自动生成 Podfile 并装好 Pod
open ios/Runner.xcworkspace        # 用 Xcode 打开
```

之后 Podfile 就存在了，再改依赖时用 `cd ios && pod install && cd ..` 即可。

在 Xcode 里：
1. 选 `Runner` target → `Signing & Capabilities`
2. 勾 `Automatically manage signing`
3. 选你的 Team（Apple ID）
4. **Bundle Identifier 改成唯一值**（如 `com.leocy.hitable`；若被占用就加后缀）

### 5.2 Info.plist 权限描述串（缺了会直接崩）

| Key | 用途 | 文案示例 |
| --- | --- | --- |
| `NSPhotoLibraryUsageDescription` | 选背景图 / 选课表截图 | 「用于选择课表截图或背景图片」 |
| `NSCameraUsageDescription` | 拍课表导入（若保留） | 「用于拍摄课表照片以导入课程」 |
| `NSUserNotificationsUsageDescription` | 通知权限说明 | 「用于上课前提醒」 |

### 5.3 WebView 教务登录（**要重点验证**）

Android 侧的实现参考：`lib/import/hit_jwts_client.dart`、`lib/presentation/hit_timetable_page.dart`

iOS 上要重新验证的点：
- WKWebView 的 Cookie 存储（`WKWebsiteDataStore`）与 Android WebView 不同
- 统一身份认证的跳转 / 重定向在 WKWebView 里可能被拦截
- 需要确认 `HitSession(jsessionId, hitToken)` 在 iOS 上能正常取到

> 建议：**先把 WebView 登录 + 读课表跑通**，这是整个 App 的价值核心。
> 其他功能（外观、小组件）都可以后补。

### 5.4 本地通知 —— **iOS 有 64 条待发上限（重要）**

`lib/notifications/reminder_planner.dart`（170 行）负责把整个学期的课程提醒排出来。

- **Android**：`AlarmManager` 没有数量上限，可以按需排
- **iOS**：`UNUserNotificationCenter` **最多只能挂 64 条待发通知**，超出的会被静默丢弃

**处理方案**（改动集中在 `reminder_planner.dart`）：
1. 只排**未来 N 天**内的提醒（比如 7 天），滚动补充
2. 或按「距现在最近的 64 条」裁剪，并在 App 回前台时重新计算
3. 加一个平台分支：`Platform.isIOS` 时启用裁剪

> 好消息：iOS 的通知**非常准时**，不像国产 Android 会被杀后台。
> 所以 iOS 侧不需要 `magic_os_guide_page.dart` 那套引导。

### 5.5 桌面小组件（**iOS 工作量最大的部分**）

Android 版是 `RemoteViews` 那套（固定槽位 + 位图圆角 + `setAlpha`），
**iOS 完全不能用**，必须重写成 **WidgetKit**：

| 项 | Android | iOS |
| --- | --- | --- |
| 技术 | RemoteViews（XML 布局） | WidgetKit + SwiftUI |
| 数据传递 | SharedPreferences（同进程可读） | **App Group 共享容器**（App 与 Widget 是**两个进程**） |
| 刷新 | 主动 `updateAppWidget` + AlarmManager | `WidgetCenter.reloadTimelines()`，系统会限流 |
| 布局能力 | 受限白名单控件 | SwiftUI 几乎无限制 ✅ |
| 圆角/背景 | 需要手工画位图 | `.clipShape(RoundedRectangle)` 一行搞定 ✅ |

**App Group 配置**（两边都要设同一个 group id）：
```
Runner target        → Signing & Capabilities → + App Groups → group.com.leocy.hitable
Widget Extension     → 同上，勾同一个 group
```

**数据契约可以复用** —— `lib/widget/next_course_widget_service.dart` 产出的 payload 结构见 §6.1，
iOS 侧只需把「写 SharedPreferences」换成「写 App Group UserDefaults」。

**小组件背景（1.2.0 刚做的功能）在 iOS 上反而更简单**：
Android 侧因为原生没法做高斯模糊，绕了一大圈（Dart 算模糊 → 存 PNG → 原生贴图）。
iOS 上 SwiftUI 直接 `.blur(radius:)` + `.opacity()` 就行，
`lib/widget/widget_background_renderer.dart`（157 行）**在 iOS 上可以不用**。

---

## 6. 小组件数据契约（iOS 需要产出同样的数据）

### 6.1 Payload 结构

来源：`lib/widget/next_course_widget_service.dart` → `buildPayload()`

```dart
{
  'dateLabel'   : '9月23日 周三',
  'weekLabel'   : '第4教学周 · 双周',      // 无学期时 = '学期未开始'
  'slotCount'   : 3,
  'slots': [
    {
      'name'      : '色彩美学',
      'meta'      : 'B108 · 刘杰',        // 「地点 · 教师」
      'startTime' : '08:00',
      'endTime'   : '09:45',
      'startMillis': 1758585600000,
      'endMillis'  : 1758591900000,
      'status'    : 'ongoing' | 'upcoming' | 'finished',
    },
  ],
  'palette'      : { 'text':…, 'sub':…, 'active':…, 'accent':…,
                     'doneText':…, 'card':…, 'activeBg':…, 'doneBg':… },  // ARGB int，浅色
  'paletteNight' : { …同样 8 个键，深色 },
  'bgPath'       : '',            // 自定义背景图路径（空 = 不启用）
  'bgDim'        : 0.0,           // 明暗蒙层 0~0.8
  'cardAlpha'    : 1.0,           // 卡片透明度 0.1~1.0
  'textAlpha'    : 1.0,           // 文字透明度 0.1~1.0
}
```

### 6.2 必须遵守的三条

1. **浅色 + 深色两套色板都要下发** —— 小组件由原生渲染，拿不到 Flutter 的 Theme
2. **排序规则**：未结束的按时间升序在前，`finished` 的沉到底部
3. **同一大节的多门课合并成一行**，名称用 ` / ` 连接，meta 用 ` | ` 连接

### 6.3 业务规则（三态判定）

| 状态 | 条件 | 显示 |
| --- | --- | --- |
| `ongoing` | `start <= now < end` | 蓝，文字「进行中」 |
| `upcoming` | `now < start` | 橙，文字 = 开课时间 |
| `finished` | `now >= end` | 灰，沉底，文字「已结束」 |

---

## 7. 两条工作线怎么分开（重要）

### 7.1 目录边界（天然清晰）

| 目录 | 归属 | 规则 |
| --- | --- | --- |
| `lib/` | **共用** | 两边都能改，但**改完两边都要跑测试** |
| `android/` | Android 线 | iOS 线**不要动** |
| `ios/` | iOS 线 | Android 线**不要动** |
| `test/` | 共用 | 新增 iOS 专有测试时用 `*_ios_test.dart` 命名 |
| `pubspec.yaml` | **共用（冲突高发区）** | 加依赖时留意别把对端的包删掉 |

### 7.2 分支策略（建议）

```
main          ← Android 稳定版（1.2.0 已发布在这里）
 └─ ios       ← iOS 开发线，从这个分支开
```

- **Android 有修复** → 提到 `main`，然后 `git merge main` 到 `ios`
- **iOS 有改动** → 留在 `ios`，验证通过后再合回 `main`
- **不要**直接在 `main` 上做 iOS 改动（会打乱 Android 的可发布状态）

### 7.3 三个必须双方同步的「契约点」

改这三处时，**必须确认 iOS 和 Android 都还能跑**：

1. **`lib/widget/next_course_widget_service.dart`** —— 小组件数据契约（§6.1）
2. **`lib/domain/appearance_settings.dart`** —— 外观设置的持久化键名（iOS/Android 共用同一套 key）
3. **`lib/data/schedule_database.dart`** —— 数据库 schema（有迁移逻辑）

### 7.4 ⚠️ 两个目录的划分与 git 状态（接手前先看这个）

**目录已经分开了**：

| 目录 | 是什么 | 状态 |
| --- | --- | --- |
| `C:\Users\leo\Projects\hitable` | **原 Android 项目**（纯净，iOS 相关一律没动过） | `git status` 干净，HEAD = `657c309` |
| `C:\Users\leo\Projects\hitable-ios` | **本项目（iOS 移植线）** | 含 `ios/` 脚手架 + 本文件，改动**尚未提交** |
| `C:\Users\leo\Projects\_backup\hitable-1.2.0-纯净源-20260926` | 原项目的纯净备份（+ 同名 `.zip`） | 逐字节校验通过 |

**历史对齐问题**：因为校园网封锁了 `github.com`，1.2.0 是**通过 GitHub API 推的**，
所以本地仓库与远端**历史不同源**（内容一致，但没有共同祖先）。

- 本地 `HEAD`：`657c309`
- 远端 `main`：`cbee4b1` → `38ea1ff`

> ⚠️ **先别急着跑 `git reset --hard origin/main`！**
> 那会把下面这些**还没提交的 iOS 改动全部丢掉**。
> **务必先提交一次**存档，再对齐。

```bash
cd C:\Users\leo\Projects\hitable-ios

# 1. 先把 iOS 改动提交，别丢
git add -A
git commit -m "iOS: 生成 ios/ 工程脚手架 + 交接文件"

# 2. 再对齐远端历史（此时重来也不会丢东西了）
git fetch origin
git reset --hard origin/main

# 3. 开 iOS 专用分支
git checkout -b ios
```

**本目录当前未提交的改动**（我为了 iOS 准备做的）：

| 状态 | 文件 | 说明 |
| --- | --- | --- |
| `?? ios/` | 新增 | iOS 工程脚手架（`flutter create --platforms=ios .` 生成），含 `ios/.gitignore` |
| `?? .metadata` | 新增 | Flutter 工程元数据，**应该提交** |
| `?? iOS-移植交接.md` | 新增 | 本文件 |
| `M analysis_options.yaml` | 改动 | 加了 `- ios/**`（把 iOS 原生目录排除出 Dart 分析）✅ 应保留 |
| `M .gitignore` | 改动 | 补了 `*.mobileprovision` / `*.p12` / `*.certSigningRequest` ✅ 应保留 |
| `M pubspec.lock` | 改动 | 只动了 `file_picker_darwin` / `file_picker_linux` 两个**桌面平台**插件，不影响 Android ✅ |
| ~~`test/widget_test.dart`~~ | 已删 | `flutter create` 塞进来的默认计数器模板测试，会失败，**已删除** |

**验证过没被破坏**：`flutter analyze` → No issues found；抽样测试全过。

---

## 8. 这个项目的既有约定（请务必遵守）

### 8.1 代码风格

- **注释写中文，解释「为什么」而不是「是什么」**
  （现有代码里大量注释在讲「为什么不用 X 而用 Y」，这是刻意的，保留这个风格）
- **不推翻重写，在已验证能跑的实现上做增量修改**
  （这条被反复强调过：宁可小步改，不要重写）
- 改动要**小步、可测、最好肉眼可辨**

### 8.2 质量门槛（每次改完必跑）

```bash
flutter analyze     # 必须 No issues found
flutter test        # 必须全绿
```

**⚠️ 已知问题：Windows 上测试运行器会抖动**

症状：某次跑出现若干 `did not complete`（**不是断言失败**），且**每次失败的文件都不同**。

- 这是 Windows 上的框架级抖动，**不是代码问题**
- **判断办法**：看到 `did not complete` 就**单独重跑那个文件**，能过即为抖动
- 若报的是 `Expected / Actual` 断言失败 → 那才是真问题

### 8.3 密钥与隐私

- **任何密钥、口令、证书一律不入库**，用 `.gitignore` 挡
- 现有 `.gitignore` 已覆盖：`*.jks`、`*.keystore`、`key.properties`、`build/`、`.dart_tool/`、`_recovery/`、`*.apk`、`PROGRESS.md`
- iOS 侧要**补上**：`*.mobileprovision`、`*.p12`、`ios/Flutter/Generated.xcconfig`、`ios/Pods/`
- **提交前用真实密钥值反查**（不是只看文件名）：

```bash
# Android 侧示例（iOS 侧换成 mobileprovision/p12 的标识串）
PW=$(grep '^storePassword=' android/key.properties | cut -d= -f2)
git diff --cached -U0 | grep -cF "$PW"        # 必须是 0
```

- **二进制文件的元数据也要扫** —— 1.2.0 发布前就抓到过一次：
  `test/fixtures/hit_timetable.xls` 的 OLE 摘要流里写着真实邮箱。
  iOS 侧的 `.xcodeproj`、`.pbxproj`、测试 fixture 同理。

### 8.4 版本号

- Android：`pubspec.yaml` 的 `version: 1.2.0+2017`，**`+` 后面是 versionCode，必须递增**
- iOS：Xcode 里的 `CFBundleShortVersionString` / `CFBundleVersion`，与 Android 独立
- 建议两边 `CFBundleShortVersionString` 对齐（都用 1.2.0），但 build number 各管各的

### 8.5 发布文档

仓库根目录有这四份，**改功能记得同步**：

```
README.md          # 项目介绍、功能列表、构建说明
CHANGELOG.md       # 更新日志（按版本倒序）
PRIVACY.md         # 隐私说明
使用说明.md         # 面向用户的安装/使用步骤
```

---

## 9. 功能 → 文件:行号 索引

### 入口与主题

| 功能 | 位置 |
| --- | --- |
| 应用入口 / ProviderScope / 主题装配 | `lib/main.dart`（61 行） |
| 主题生成（种子色、圆角、紧凑度） | `lib/presentation/app_theme.dart`（154 行） |
| 主页背景（预设图案 / 自定义图 / 模糊 / 明暗） | `lib/presentation/app_background.dart`（264 行） |
| 功能开关 | `lib/feature_flags.dart`（16 行） |

### 首页与课表

| 功能 | 位置 |
| --- | --- |
| 首页（今日/本周、瀑布流/表格两种排布） | `lib/presentation/home_page.dart`（1,388 行） |
| 页脚署名 `Adapted by Leocy` | `lib/presentation/home_page.dart:272` |

### 外观设置（最大的单文件）

| 功能 | 位置 |
| --- | --- |
| 外观设置**数据模型**（6 预设配色、小组件配色、背景、透明度…） | `lib/domain/appearance_settings.dart`（726 行） |
| 外观设置**页面** | `lib/presentation/appearance_settings_page.dart`（2,138 行） |
| 外观设置持久化 controller | `lib/application/appearance_controller.dart`（60 行） |

### 排课内核（纯逻辑，iOS 直接可用）

| 功能 | 位置 |
| --- | --- |
| 课表引擎（按日期取课、周次判定） | `lib/domain/schedule_engine.dart`（85 行） |
| 数据模型（Course / CourseSession / Term / WeekRule） | `lib/domain/schedule_models.dart`（198 行） |
| 周次规则解析（`4-17`、`odd:4-17`、`4-16!8`） | `lib/domain/week_rule_parser.dart`（81 行） |
| 课程冲突检测 | `lib/domain/course_conflict.dart`（65 行） |
| 课表状态 controller | `lib/application/schedule_controller.dart`（321 行） |

### 数据层

| 功能 | 位置 |
| --- | --- |
| SQLite 数据库 + schema 迁移 | `lib/data/schedule_database.dart`（512 行） |
| JSON 备份 / 恢复 | `lib/data/schedule_backup_codec.dart`（228 行） |
| 国家节假日 + 调休 | `lib/data/national_holiday_service.dart`（109 行） |

### 教务导入（iOS 需重新验证的关键路径）

| 功能 | 位置 |
| --- | --- |
| 哈工大教务接口客户端（`POST /kbcx/queryGrkb`） | `lib/import/hit_jwts_client.dart`（315 行） |
| 课表 HTML/接口结果解析 | `lib/import/hit_timetable_import.dart`（332 行） |
| 学期 / 作息导入 | `lib/import/term_import.dart`（230 行） |
| 通用导入编排（CSV/XLSX/图片/网页） | `lib/import/course_import.dart`（431 行） |
| `.xls` 二进制解析（自写 BIFF 读取器） | `lib/import/xls_reader.dart`（512 行） |
| WebView 登录页 | `lib/presentation/hit_timetable_page.dart`（337 行） |
| 导入预览 / 纠错 | `lib/presentation/import_preview_page.dart`（330 行） |

### 通知（iOS 要改动）

| 功能 | 位置 |
| --- | --- |
| 通知服务（`flutter_local_notifications` 封装） | `lib/notifications/notification_service.dart`（201 行） |
| **提醒规划（iOS 64 条上限要在这里裁剪）** | `lib/notifications/reminder_planner.dart`（170 行） |
| 生命周期（App 回前台重排 + 小组件同步） | `lib/notifications/notification_lifecycle.dart`（224 行） |
| 通知设置模型 | `lib/domain/notification_settings.dart`（48 行） |
| 通知设置页（含「国产 Android 后台设置」入口 :144） | `lib/presentation/notification_settings_page.dart`（378 行） |

### 桌面小组件

| 功能 | 位置 |
| --- | --- |
| **数据契约（iOS 照这个产出）** | `lib/widget/next_course_widget_service.dart`（304 行） |
| 背景图预处理（**iOS 可不用**，SwiftUI 原生支持模糊） | `lib/widget/widget_background_renderer.dart`（157 行） |
| Android 原生渲染（→ Swift 重写） | `android/app/src/main/kotlin/com/leocy/hitable/NextCourseWidget.kt` |
| Android 通道接收端（→ AppDelegate 重写） | `android/app/src/main/kotlin/com/leocy/hitable/MainActivity.kt` |

### 其它页面

| 功能 | 位置 |
| --- | --- |
| 国产 Android 后台设置引导（**iOS 用不上**） | `lib/presentation/magic_os_guide_page.dart`（241 行） |
| 首次使用教程 | `lib/presentation/tutorial_page.dart`（149 行） |
| 学期设置 | `lib/presentation/term_setup_page.dart`（333 行） |
| 手工添加课程 | `lib/presentation/manual_course_page.dart`（400 行） |
| 备份与恢复 | `lib/presentation/data_management_page.dart`（131 行） |

---

## 10. 命令速查

```bash
# ---- 在 Windows 上就能做的（Dart 层）----
flutter analyze                 # 必须 No issues found
flutter test                    # 全部测试
flutter test test/xxx_test.dart # 单文件（抖动时用这个重跑）

# ---- 只能在 macOS 上做的 ----
cd ios && pod install && cd ..
open ios/Runner.xcworkspace     # Xcode 配置签名
flutter run -d <device-id>      # 真机调试
flutter build ipa               # 出 TestFlight 包

# ---- 常用小工具 ----
flutter devices                 # 列出设备
flutter clean                   # 清构建缓存（Podfile 出问题时常用）
cd ios && rm -rf Pods Podfile.lock && pod install   # Pod 依赖彻底重来
```

---

## 11. 一句话总结优先级

如果时间有限，按这个顺序做 iOS：

1. **macOS 环境 + 签名**（不做完，后面全是空谈）
2. **WebView 教务登录 + 读课表**（App 的核心价值，且 iOS 上最可能踩坑）
3. **课表展示**（Dart 层直接复用，几乎零成本）
4. **本地通知**（加 64 条裁剪逻辑）
5. **桌面小组件 WidgetKit**（工作量最大，但数据契约现成）

外观美化那 6,000 多行 UI 代码基本可以原样跑起来，**不用操心**。

---

> 有疑问时优先看 `PROGRESS.md`（本地，未入库）——
> 那里记录了这个项目从 1.0.0 到 1.2.0 每一次改动的**原因**和**踩过的坑**，
> 是比 git log 信息量大得多的决策档案。
