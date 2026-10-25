import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 将选定图标规范化为 iOS 通用图标：1024 × 1024、sRGB、无透明通道。
/// 这里只进行尺寸与文件格式转换，保留原设计、比例、颜色与完整画面。
func prepareIcon(input: String, output: String) throws {
    let sourceURL = URL(fileURLWithPath: input)
    let outputURL = URL(fileURLWithPath: output)
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == image.height else {
        throw NSError(domain: "RunningLogIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "输入必须是可读取的正方形图片。"])
    }
    let dimension = 1024
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: dimension, height: dimension, bitsPerComponent: 8,
                                  bytesPerRow: dimension * 4, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw NSError(domain: "RunningLogIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法创建图标画布。"])
    }
    // 明确使用无透明通道画布，避免仅将透明像素涂满但 PNG 仍带 Alpha 通道。
    let rect = CGRect(x: 0, y: 0, width: dimension, height: dimension)
    context.setFillColor(CGColor(red: 0.02, green: 0.25, blue: 0.28, alpha: 1))
    context.fill(rect)
    context.interpolationQuality = .high
    context.draw(image, in: rect)
    guard let result = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "RunningLogIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法创建图标输出文件。"])
    }
    CGImageDestinationAddImage(destination, result, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "RunningLogIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "图标写入失败。"])
    }
    print("图标已保存：\(outputURL.path)（1024 × 1024，无透明通道）")
}

// 使用明确的输入和输出参数，避免脚本意外覆盖其他资源。
guard CommandLine.arguments.count == 3 else {
    fputs("用法：swift prepare_app_icon.swift 输入图片 输出图片\n", stderr)
    exit(1)
}
do {
    try prepareIcon(input: CommandLine.arguments[1], output: CommandLine.arguments[2])
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
