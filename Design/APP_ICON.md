# 跑步手记应用图标

设计主题：以青绿色、荧光绿和动态跑者表现持续跑步，以跑道圆弧呼应训练进度。图标不包含文字，便于在手机主屏幕小尺寸识别。

生成方式：内置 ImageGen 工具。生成后仅进行用于 iOS 的尺寸与不透明 PNG 格式规范化，不修改主体设计。

此前几乎全黑的图标保留在 `Archive/AppIcon-before.png`，便于回溯。最终资源由 `RunningLog/Assets.xcassets/AppIcon.appiconset/Contents.json` 指定。

## 生成提示词

```text
Use case: logo-brand. Create a single production-ready iOS app icon for a Chinese personal running journal app called 跑步手记. Brand context: native app UI uses teal and clean white cards; existing intended palette is deep petrol teal with fresh lime green. Deliver ONLY the square icon artwork, exactly 1024 by 1024 pixels, completely opaque full-bleed background, no pre-rounded outer corners, no framing or device mockup. Design: a distinctive, clean dynamic running figure formed from a few bold flowing geometric strokes, striding toward the upper-right, subtly interwoven with one clean oval running-track arc suggesting a progress ring and daily consistency. Figure in vibrant fresh lime green, track arc in a quieter mint/teal against a deep petrol teal background with restrained smooth gradient. Confident, balanced, vector-like editorial mark, precise smooth curves, large generous central symbol with optical safe margin 15%, high contrast and immediately legible at 60 pixels. Refined premium fitness app identity, energetic but calm. Avoid extra pictograms, statistics bars, lettering, text, letters, numbers, watermarks, thin detail, borders, badges, shine, 3D mockups, photographic texture, or excessive shadows. Original visual design, not a copied sports brand logo.
```

## 资源与格式

最终文件：`RunningLog/Assets.xcassets/AppIcon.appiconset/AppIcon-Running.png`。

Xcode 继续使用 `AppIcon` 资源集；不预绘制外部圆角，交由 iOS 按系统外观裁切。图标使用 sRGB，无透明通道。

如需将以后选定的正方形图片转为相同格式，使用 `Scripts/prepare_app_icon.swift`，依次传入输入与输出路径。脚本只做无损 PNG 编码及必要的尺寸规范化，不重新生成或修改主体设计。
