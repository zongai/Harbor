import Foundation
import ImageIO
import UIKit

/// ImageIO 降采样：按目标像素边长解码，避免 4000×3000 原图进内存
enum ImageDownsampling {
    /// 从数据解码为不超过 maxPixel 边长的 UIImage
    static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let maxPixel = max(32, maxPixel)
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }

    /// 按屏幕 scale 与逻辑点尺寸计算 maxPixel
    static func maxPixel(forSidePoints side: CGFloat, scale: CGFloat = UIScreen.main.scale) -> CGFloat {
        ceil(side * max(scale, 2))
    }
}
