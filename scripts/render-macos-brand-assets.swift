#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum BrandAssetError: Error, LocalizedError {
    case unreadableImage(URL)
    case unableToCreateContext
    case unableToWrite(URL)
    case missingVisiblePixels(URL)

    var errorDescription: String? {
        switch self {
        case let .unreadableImage(url): "Unable to read image at \(url.path)"
        case .unableToCreateContext: "Unable to create a CoreGraphics bitmap context"
        case let .unableToWrite(url): "Unable to write image at \(url.path)"
        case let .missingVisiblePixels(url): "No visible dragon pixels were found in \(url.path)"
        }
    }
}

struct Raster {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(image: CGImage) throws {
        width = image.width
        height = image.height
        pixels = Array(repeating: 0, count: width * height * 4)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            throw BrandAssetError.unableToCreateContext
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func pixel(atX x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let offset = (y * width + x) * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
    }

    func isVisible(atX x: Int, y: Int) -> Bool {
        let color = pixel(atX: x, y: y)
        return color.alpha > 12 && max(color.red, color.green, color.blue) > 24
    }

    func visibleBounds(in region: CGRect? = nil, source: URL) throws -> CGRect {
        let bounded = (region ?? CGRect(x: 0, y: 0, width: width, height: height))
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
            .integral
        var minimumX = Int.max
        var minimumY = Int.max
        var maximumX = Int.min
        var maximumY = Int.min

        for y in Int(bounded.minY)..<Int(bounded.maxY) {
            for x in Int(bounded.minX)..<Int(bounded.maxX) where isVisible(atX: x, y: y) {
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }

        guard minimumX <= maximumX, minimumY <= maximumY else {
            throw BrandAssetError.missingVisiblePixels(source)
        }
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX + 1,
            height: maximumY - minimumY + 1
        )
    }

    func cropped(to bounds: CGRect) -> Raster {
        let rectangle = bounds.integral
        let cropWidth = Int(rectangle.width)
        let cropHeight = Int(rectangle.height)
        var result = Array(repeating: UInt8(0), count: cropWidth * cropHeight * 4)
        for y in 0..<cropHeight {
            let sourceOffset = ((Int(rectangle.minY) + y) * width + Int(rectangle.minX)) * 4
            let destinationOffset = y * cropWidth * 4
            result.replaceSubrange(
                destinationOffset..<(destinationOffset + cropWidth * 4),
                with: pixels[sourceOffset..<(sourceOffset + cropWidth * 4)]
            )
        }
        return Raster(width: cropWidth, height: cropHeight, pixels: result)
    }

    func rendering(body: Bool) -> Raster {
        var result = Array(repeating: UInt8(0), count: pixels.count)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let red = pixels[offset]
                let green = pixels[offset + 1]
                let blue = pixels[offset + 2]
                let alpha = pixels[offset + 3]
                let isYellow = red > 170 && green > 90 && green < 230 && blue < 100 && red > green + 30
                let visible = alpha > 12 && max(red, green, blue) > 24
                let belongsToLayer = body ? !isYellow : isYellow
                guard visible, belongsToLayer else { continue }

                if body {
                    result[offset] = 255
                    result[offset + 1] = 255
                    result[offset + 2] = 255
                } else {
                    result[offset] = red
                    result[offset + 1] = green
                    result[offset + 2] = blue
                }
                result[offset + 3] = alpha
            }
        }
        return Raster(width: width, height: height, pixels: result)
    }

    func transparentArtwork() -> Raster {
        var result = Array(repeating: UInt8(0), count: pixels.count)
        for y in 0..<height {
            for x in 0..<width where isVisible(atX: x, y: y) {
                let offset = (y * width + x) * 4
                result[offset] = pixels[offset]
                result[offset + 1] = pixels[offset + 1]
                result[offset + 2] = pixels[offset + 2]
                result[offset + 3] = pixels[offset + 3]
            }
        }
        return Raster(width: width, height: height, pixels: result)
    }

    func cgImage() throws -> CGImage {
        var mutablePixels = pixels
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: &mutablePixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ), let image = context.makeImage() else {
            throw BrandAssetError.unableToCreateContext
        }
        return image
    }
}

func loadRaster(_ url: URL) throws -> Raster {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw BrandAssetError.unreadableImage(url)
    }
    return try Raster(image: image)
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw BrandAssetError.unableToWrite(url)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw BrandAssetError.unableToWrite(url)
    }
}

func rendered(_ raster: Raster, canvas: CGSize) throws -> CGImage {
    let width = Int(canvas.width)
    let height = Int(canvas.height)
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo
    ) else {
        throw BrandAssetError.unableToCreateContext
    }
    context.clear(CGRect(origin: .zero, size: canvas))
    context.interpolationQuality = .high
    context.draw(try raster.cgImage(), in: CGRect(origin: .zero, size: canvas))
    guard let image = context.makeImage() else { throw BrandAssetError.unableToCreateContext }
    return image
}

func renderIcon(from dragon: Raster, size: Int) throws -> CGImage {
    let canvas = CGSize(width: size, height: size)
    let content = CGSize(width: CGFloat(size) * 0.78, height: CGFloat(size) * 0.78)
    let scale = min(content.width / CGFloat(dragon.width), content.height / CGFloat(dragon.height))
    let drawSize = CGSize(width: CGFloat(dragon.width) * scale, height: CGFloat(dragon.height) * scale)
    let origin = CGPoint(x: (canvas.width - drawSize.width) / 2, y: (canvas.height - drawSize.height) / 2)
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo
    ) else {
        throw BrandAssetError.unableToCreateContext
    }
    context.clear(CGRect(origin: .zero, size: canvas))
    context.interpolationQuality = .high
    context.draw(try dragon.cgImage(), in: CGRect(origin: origin, size: drawSize))
    guard let image = context.makeImage() else { throw BrandAssetError.unableToCreateContext }
    return image
}

let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let brandDirectory = repository.appendingPathComponent("assets/brand", isDirectory: true)
let resourcesDirectory = repository.appendingPathComponent("apps/zanryo-macos/Resources", isDirectory: true)
let statusSource = brandDirectory.appendingPathComponent("zanryo-status-tail-source.png")
let dragonSource = brandDirectory.appendingPathComponent("zanryo-dragon-z-source.png")

func prepareSources(from inputDirectory: URL) throws {
    let approvedTail = inputDirectory.appendingPathComponent("zanryo-status-dragon-tail-concept-v1.png")
    let approvedLogo = inputDirectory.appendingPathComponent("zanryo-dragon-logo-approved-concept.png")
    try FileManager.default.createDirectory(at: brandDirectory, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: statusSource)
    try FileManager.default.copyItem(at: approvedTail, to: statusSource)

    let logo = try loadRaster(approvedLogo)
    // The top lockup is the approved standalone dragon-Z; the lower rows are sizing samples and wordmarks.
    let upperLockup = CGRect(x: 480, y: 0, width: 570, height: 400)
    let crop = try logo.visibleBounds(in: upperLockup, source: approvedLogo)
    try writePNG(try logo.cropped(to: crop).transparentArtwork().cgImage(), to: dragonSource)
}

func renderProductionAssets() throws {
    let tail = try loadRaster(statusSource)
    let visibleTail = try tail.cropped(to: tail.visibleBounds(source: statusSource))

    // A single 3x PNG avoids Xcode flattening the `@1x/@2x/@3x` loose files
    // into a 1x TIFF, which erased the very small yellow tip in the menu bar.
    let targetHeight = 54
    let targetWidth = Int((CGFloat(visibleTail.width) / CGFloat(visibleTail.height) * CGFloat(targetHeight)).rounded(.up))
    try writePNG(
        try rendered(visibleTail.rendering(body: true), canvas: CGSize(width: targetWidth, height: targetHeight)),
        to: resourcesDirectory.appendingPathComponent("zanryo-status-body.png")
    )
    try writePNG(
        try rendered(visibleTail.rendering(body: false), canvas: CGSize(width: targetWidth, height: targetHeight)),
        to: resourcesDirectory.appendingPathComponent("zanryo-status-tip.png")
    )

    let dragon = try loadRaster(dragonSource)
    let iconDirectory = resourcesDirectory.appendingPathComponent("Assets.xcassets/AppIcon.appiconset", isDirectory: true)
    let iconSizes: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for icon in iconSizes {
        try writePNG(try renderIcon(from: dragon, size: icon.pixels), to: iconDirectory.appendingPathComponent(icon.name))
    }
}

do {
    if CommandLine.arguments.dropFirst().first == "--prepare-sources" {
        guard let directory = CommandLine.arguments.dropFirst(2).first else {
            fatalError("Usage: swift scripts/render-macos-brand-assets.swift --prepare-sources <approved-screenshot-directory>")
        }
        try prepareSources(from: URL(fileURLWithPath: directory, isDirectory: true))
    }
    try renderProductionAssets()
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
