# 翻译与本地化 / Localization

当前支持 `zh-Hans`（简体中文）与 `en`（English），默认跟随系统，无匹配语言时回退英文。应用内设置会持久保存；活动会话结束后再切换。

应用内中英文名称均为“OpenLightCapture”。Finder 与系统弹窗读取 `InfoPlist.xcstrings`，按系统为应用选择的语言显示；应用内语言切换不会重命名磁盘上的 `OpenLightCapture.app`。

## 资源与入口

| 文件 | 用途 |
|---|---|
| [LocalizationConfig.json](../LightCapture/Resources/LocalizationConfig.json) | 可选语言、原生名称、默认值与回退语言 |
| [Localizable.xcstrings](../LightCapture/Resources/Localizable.xcstrings) | 用户界面、错误、动态提示和文件名前缀 |
| [InfoPlist.xcstrings](../LightCapture/Resources/InfoPlist.xcstrings) | 系统读取的应用显示名 |
| [L10n.swift](../LightCapture/Localization/L10n.swift) | 稳定语义 key、默认英文和类型明确的参数入口 |
| [LocalizationStore.swift](../LightCapture/Localization/LocalizationStore.swift) | 偏好、有效语言、等待生效与快捷键录入保护 |

## 修正已有译文

在 String Catalog 中编辑对应语言，保留 key 和参数语义。英文基础文本变化时同步检查 `L10n.swift` 的默认值，以免缺译文时出现旧口径。不要翻译 SF Symbols 名称、控件 identifier、Bundle ID、扩展名、日志标识或用户输入。

多参数消息按整句翻译，允许调整显示顺序，但必须保留每个参数的位置与类型。`long.running` 的秒数使用原生复数，英文 `1 second` 与 `2 seconds` 应分别检查。不要拼接单词来形成句子。

```sh
python3 scripts/verify-localizations.py
```

该脚本检查调用 key、语言集合、翻译状态及格式参数；仍需要人工检查语义与布局。报告问题可提供语言、页面、key、当前译文与建议译文。

## 新增语言

1. 先通过 Issue 对齐语言范围和维护方式，再添加译文。
2. 在两个 catalog 中补齐语言，并在 JSON 清单加入 BCP 47 标识与原生名称。
3. 更新 `project.yml` 的语言声明并重新生成工程。
4. 核对 `LocalizationTests.swift` 的首期语言断言，以及 `verify-localizations.py` 中“本期不包含繁体中文”的检查；扩展范围时一并更新对应测试/规则。
5. 检查缺译文回退、参数、复数、文字工具、设置、长图面板、tooltip 与无障碍标签。
6. 构建并用 `--app` 检查实际资源，而不只看源 catalog：

```sh
python3 scripts/verify-localizations.py --app build/OpenLightCapture.app
```

新增资源随应用重新发布后可用；当前不加载外部语言包。右到左语言需要额外验证布局方向，不能仅增加清单项。

## English

Use the catalogs and semantic `L10n` accessors above. Keep the English fallback in sync when source wording changes. Translate complete messages, preserve placeholder positions/types, and test plural forms. Do not translate symbols, identifiers, paths/protocol names, or user-entered annotations.

Run the source validator, then inspect both language semantics and actual UI layout. Adding a language requires both catalogs, the JSON manifest, XcodeGen configuration, and intentional updates to tests that assert the initial language scope. Verify compiled resources with `--app`. New languages ship in a rebuilt app; external packs and right-to-left layouts are not implicitly supported.
