# Enchant 素材与许可

## 入口

| 位置 | 内容 |
| --- | --- |
| `images/` | 原版／增强 Logo、原版／增强附魔剑、未附魔剑、书插画；插画 PNG 保留透明通道，AppIcon 为不透明方图 |
| `icons/` | 12 个 16 格像素 SVG；统一材质明暗，包含原创设置齿轮和独立回收站 |
| `fonts/` | Fusion Pixel、Silkscreen Regular／Bold 与 OFL 许可证 |
| `source/` | 剑母版及导出脚本、预览模板与 CSS |
| `design-tokens.json` | 颜色、字体和布局依据 |
| `font-manifest.json` | CoreText 验证的真实 PostScript 名称 |
| `generation-prompts.json` | imagegen 原图与编辑提示 |
| `preview.html` | 生成的交互预览，使用样例数据 |

## 更新

在项目根目录运行：

```sh
python3 scripts/generate-pixel-icons.py
swift scripts/prepare-assets.swift
python3 scripts/build-preview.py
```

预览由 `source/preview-template.html`、`source/preview.css` 和素材生成，不直接编辑大段嵌入数据。原生资源统一准备至 `App/Resources`，两端从同一资源目录取图案。

中英文资源位于 `App/Resources/Localizable.xcstrings` 和 `InfoPlist.xcstrings`，随两端应用打包，由系统选择语言。图像和字体共用，入口名称遵循 [README](../README.md#系统语言与措辞)。

用户备注、网址、外部健康来源名称和 ISO 日期键保留原文；应用自有来源标记只在显示层本地化。预览使用样例数据，说明放在设备界面外部；语言和布局以原生检查为准。

剑母版改动的导出路径保留为 `source/render-assets.py` 和 `source/export-assets.swift`。未附魔剑是原附魔剑的 imagegen 编辑版本，仅移除紫色附魔效果，生成记录保存在同一 JSON 中。

## 来源与分发

插画由内置 imagegen 制作。当前 Logo 使用 `images/enhanced-app-icon.png`，完成及导航使用 `images/enhanced-sword.png`；增强版以原图为参考编辑，保留剑刃、护手和握柄，只调整紫色光泽与像素效果。原剑、原 Logo、书插画及母版均保留，提示与参考图见 `generation-prompts.json`。像素图标由项目绘制，不复制 Minecraft 纹理或标志。AppIcon、图像资源和字体注册已接入工程。

字体未修改，随应用保留许可证：

- [Fusion Pixel](https://github.com/TakWolf/fusion-pixel-font)：`FusionPixel-OFL.txt`。
- [Silkscreen](https://github.com/google/fonts/tree/main/ofl/silkscreen)：`Silkscreen-OFL.txt`。

字体及插画不从运行中的外部服务加载。预览文件可独立打开。

图标脚本生成原生 Canvas 和导航 PNG，预览内嵌同一 SVG。设置使用原创像素齿轮，回收站使用独立像素桶，边界与剑、书导航资源一致。修改 SVG 后按上述顺序生成。
