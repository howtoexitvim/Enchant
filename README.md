# Enchant

以 Apple Watch 为主的私人活动手账。开始、暂停、结束、心率和备注都可以在手表完成；iPhone 提供更大的月／年日历和文字编辑空间。数据先存本机，通过配对设备同步，无账号或服务器。

## 运行

打开 `Enchant.xcodeproj`，选择 `Enchant` 或 `EnchantWatch` scheme。最低 iOS 17 / watchOS 10。真机安装需在两个应用 target 的 Signing & Capabilities 中选择自己的开发团队，再运行至配对设备。

[界面预览](assets/preview.html) 可直接打开，字体和图案已内嵌。预览使用样例数据，健康与动作数值不代表真实采集；样例说明放在设备界面外部。原生应用只显示实际样本。

HTML 右上角提供设备外的「中文 / EN」切换，初次打开默认系统语言，之后保存当前浏览器的选择。切换不重载页面，保留场景、会话、编辑草稿和搜索；原生应用仍跟随系统，不增加语言开关。

```sh
swift test
xcodebuild -project Enchant.xcodeproj -scheme Enchant \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/EnchantBuild CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Enchant.xcodeproj -scheme Enchant \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/EnchantBuild CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO test
```

Debug 启动参数 `-demo` 使用隔离的演示资料库，`-ui-testing` 使用隔离的自动化测试资料库；均不写入日常记录。Release 不启用这些参数。

## 系统语言与措辞

原生 iPhone 和 Watch 应用支持简体中文与英文，由系统为各应用选择界面语言，不另设应用内语言开关。标签、状态、错误、图表说明和系统权限用途说明随界面语言显示；月份名称等展示日期也采用界面语言。

| 英文 | 中文 | 用途 |
| --- | --- | --- |
| Enchant | 附魔 | 功能入口与开始操作；产品名保持 Enchant |
| Journal | 手账 | 底部入口与短导航 |
| Spellbook | 魔法手账 | 完整手账入口与页面标题 |
| Settings | 设置 | 偏好入口 |
| Note | 备注 | 完成页入口与备注内容 |
| Done | 完成 | 结束当前查看流程 |

说明优先表达功能和状态，避免反复使用口号或故事化修饰。沿用表中的现有入口和标题，Watch 优先使用短名称。传输确认使用“传输完成”，永久拒绝也属于已处理，不能写成记录已成功合并。用户备注、网址、外部健康来源名称和 ISO 日期键 `yyyy-MM-dd` 保留原文；本地化不改动记录内容、保存时区或数据格式。

## 当前范围

Watch 首页只有剑、开始、手账和设置。自动开始在设置开启，前台待机，离开暂停、返回恢复。记录页显示活动时长、心率及估算次数；结束后自动保存。手账采用列表，详情按摘要、心率、备注横向翻页。网址直接写在备注中。

iPhone 提供同一套记录、详情、备注和回收站，以及月／年日历和搜索。主界面固定一屏；大量记录、长备注和系统键盘使用局部滚动。没有独立自动监测页、手动补记、应用锁、链接表单或备份导入导出。

## 代码与维护

| 目录 | 职责 |
| --- | --- |
| `Sources/EnchantCore` | 会话状态、真实样本、动作判定、本地版本与设备同步数据 |
| `App/Shared` | 状态协调、HealthKit、Core Motion、WatchConnectivity、主题和反馈 |
| `App/Watch` | 主设备界面；新增功能优先验证手表布局 |
| `App/iOS` | 配套日历、浏览和编辑 |
| `App/Resources` | 共用素材、中英文文案、权限用途说明和隐私清单 |
| `Tests/EnchantCoreTests` | 时长、中断、存储、同步和校验测试 |
| `App/Tests`、`App/UITests` | 应用状态与原生操作流程测试 |
| `assets/source` | 插画母版与预览模板；不直接编辑生成的预览文件 |
| `scripts` | 素材、工程和预览的可重复生成脚本 |

更新像素图标运行 `python3 scripts/generate-pixel-icons.py`；更新原生素材运行 `swift scripts/prepare-assets.swift`，随后运行 `python3 scripts/build-preview.py` 更新预览；导航图标由同一资源生成。工程源文件或 target 发生变化时，可使用已安装的 Ruby `xcodeproj` gem 执行 `ruby scripts/generate-project.rb`。日常开发直接使用现有工程。

两端共用 `PrivacyInfo.xcprivacy`，声明用于私有偏好的 UserDefaults 访问理由 CA92.1，无追踪或开发者服务器数据收集。新增系统 API 或外部服务时须同步更新声明；格式见 [Apple 隐私清单说明](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)。

预览交互回归使用 jsdom，不启动浏览器：

```sh
npm install --prefix /tmp/enchant-preview-tests jsdom@29.1.1 --no-audit --no-fund
NODE_PATH=/tmp/enchant-preview-tests/node_modules node scripts/test-preview.cjs
python3 scripts/test-localization.py
```

## 采集与指标

| 数据 | 实际来源与含义 |
| --- | --- |
| 时长 | 起止时间减去暂停区间；中断停在检查点或系统提供的结束时间 |
| 次数 | Watch `CMDeviceMotion.userAcceleration` 的往复周期估算；同一轴加速度两次合格正负交替计一个周期，不是生理事件计数 |
| 自动开始 | 设置开启后仅活跃前台待机；至少八次连续加速度正负交替、持续三秒且节奏相对稳定才产生候选 |
| 实时心率 | HealthKit builder 的最近实际读数；超过 30 秒不再作为当前心率显示 |
| 归档心率 | HealthKit 数量序列中的实际测量点，保留时间、来源及身份；平均值是有效留存读数的算术平均 |
| 曲线与峰值 | 与平均值使用同一份有效读数，排除暂停区间，空缺处断开 |

动作采集请求频率为 20Hz，默认阈值 0.12g；不同动作、佩戴和方向可能导致漏计或误计。重启采集、主轴改变和长间隔会清空未完成周期，保留已完成次数。无有效动作样本时显示 `--`；收到真实静止样本时，零才表示已测得。iPhone 自行开始只记时，不虚构 Watch 次数或心率。HTML 的 126／98 等数值来自样例；日常原生记录不使用它们。

采集前请求开始提示，结束提示等待健康采集收尾；后台结束只在下一次前台显示时提示一次。声音开关控制应用 WAV，触感开关控制系统反馈；Watch 系统触感可能伴随系统音调，听觉表现还受设备静音状态影响。

健康会话使用 `.other`，不保存训练记录。自动开始不具备全天后台唤醒能力；缺少健康会话运行条件时，离开前台会暂停记录。权限请求完成不等于可读取心率，没有有效读数仍显示 `--`。崩溃恢复先清理遗留系统会话，保留本地中断记录，继续操作由用户选择。

参考 [Apple Core Motion](https://developer.apple.com/documentation/coremotion/getting-processed-device-motion-data)、[HealthKit 数量序列](https://developer.apple.com/documentation/healthkit/hkquantityseriessamplequerydescriptor)、[Watch 触感](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/play(_:))。旧健康记录可能被系统压缩，不能用本应用的留存读数平均值冒充 HealthKit 的加权统计。

## 验证状态

2026-10-08 本轮验证使用 Xcode 26.3，原生界面流程在 iPhone 16e / iOS 26.2 模拟器运行，覆盖简体中文和英文。

| 验证范围 | 当前测试覆盖 | 已验证结果 |
| --- | --- | --- |
| 共享核心 | 计时、暂停、中断、样本、原子保存、容量边界、重复及离线合并、删除恢复、无效数据 | 66 项通过 |
| 原生状态与资源 | 采集生命周期、真实时间、授权和恢复竞态、最终样本保留、反馈时机、失败重试、双端数据往返、资源及本地化 | 42 项通过 |
| iPhone UI | 开始暂停结束、重开、备注与网址、草稿、删除恢复、日历搜索、偏好持久化、英文界面保留用户内容 | 8 项通过 |
| 离线预览 | 页面交互、记录和草稿、搜索、删除恢复、异常状态及语言切换保留现场 | 16 组通过：14 中文、2 英文，另含语言优先级／回退检查 |

静态资源检查覆盖 271 条中英文文案、格式参数顺序和三项系统权限用途说明。中英文原生完整流程已通过；英文保存备注与网址后，切回中文重开确认内容保持原文。本轮采集修正后重新运行全部 66／42／8 项，均通过。新增 19 项原生采集流程回归，涵盖传感器断采、暂停恢复、授权中途开启、系统时间事件、快速重开、待保存结果收尾样本和一次性反馈。测试先复现旧实现的问题，再验证修复。

前一轮已验证 Watch SE3 40mm、Series 11 42／46mm、Ultra 3 49mm 模拟器在 watchOS 26.2 的中英文首页、完成、备注、设置和摘要布局，未见重叠或截断；截图使用隔离样例资料库。小表设置采用 38／40pt 视觉卡片、44pt 触摸区、12pt 图标与文字、2pt 行距；46／49mm 保留原布局。本轮另复核 42mm 中英文无心率／无动作样本完成页，`--` 与操作按钮排版正常。预览在 1100px 与 430px 窗口实测语言切换、独立草稿保留和重开语言选择，页首无溢出。

最终 iOS／watchOS Release 设备编译通过，未签名。两端产物及手机内嵌的 Watch 应用均包含隐私清单、271 条中英文文案、权限说明和字体；Watch 包含 arm64_32／arm64 架构。详细验收和设备边界见项目日志。

模拟器无法验证真实心率、动作误判率、后台耗电及真实配对传输。相关服务已接入，实表验收需在签名安装后完成；自动开始不承诺全天后台唤醒。

## 许可

项目代码采用 [MIT 许可证](LICENSE)。随附字体保留各自的 SIL Open Font License，详见[素材说明](assets/README.md)。
