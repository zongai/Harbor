import Foundation
import ImageIO
import UIKit

/// ImageIO 降采样：按目标像素边长解码，避免超大原图进内存，同时保留屏上清晰度
enum ImageDownsampling {
    /// 阅读配图默认逻辑宽度上限（点）
    static let articleMaxSidePoints: CGFloat = 680
    /// 列表图标默认边长（点）
    static let iconSidePoints: CGFloat = 40

    /// 从数据解码为不超过 maxPixel 边长的 UIImage（保持 EXIF 方向）
    static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let maxPixel = max(64, maxPixel)
        let srcOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, srcOpts as CFDictionary) else {
            return UIImage(data: data)
        }
        // FromImageAlways + Transform：方向正确；若源已有更小缩略图则仍强制按 max 生成，避免糊
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel.rounded(.up))
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    /// 按屏幕 scale 与逻辑点尺寸计算 maxPixel（至少 2×，Retina 可用 3× 更清晰）
    static func maxPixel(forSidePoints side: CGFloat, scale: CGFloat? = nil) -> CGFloat {
        let s = scale ?? UIScreen.main.scale
        let effective = max(s, 2)
        // 略抬高一点避免压缩后发糊（尤其是配图）
        return ceil(side * effective * 1.15)
    }

    static func articleMaxPixel() -> CGFloat {
        let side = min(UIScreen.main.bounds.width, articleMaxSidePoints)
        return maxPixel(forSidePoints: side)
    }

    static func iconMaxPixel(sidePoints: CGFloat = iconSidePoints) -> CGFloat {
        maxPixel(forSidePoints: sidePoints)
    }
}
