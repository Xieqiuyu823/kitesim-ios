import Foundation
import CoreGraphics
import ImageIO
import OnnxRuntimeBindings

// MARK: - 图像预处理：复刻 ddddocr / 安卓 CaptchaOcr.kt 的推理输入

/// 流程：等比缩放到高 64（宽 = int(w*64/h)）→ 灰度（PIL 'L' 公式）
/// → 面积平均降采样 → 归一化 /255 → 张量 (1, 1, 64, W)
enum CaptchaPreprocessor {

    static let targetHeight = 64

    /// 行序说明（v1.0 的严重 bug 就在这里）：
    ///
    /// CGBitmapContext 的像素缓冲第 0 行对应图像最上面一行（CoreGraphics 设备坐标 y 向上，
    /// 缓冲最后一行才是 y=0）。所以按默认坐标直接 `draw` 出来的缓冲已经是「自上而下」，
    /// 与 PIL / Android `Bitmap.getPixels` 的行序完全一致，**不需要任何翻转**。
    ///
    /// v1.0 在 draw 之前多做了一次 `translateBy(0,h) + scaleBy(1,-1)`，等于把整张验证码
    /// 上下镜像后再喂给模型，识别结果必然是乱码/非 4 位，表现为「图形验证码识别失败」。
    /// 保留该参数只是为了在极端情况下做一次兜底尝试（见 CaptchaOCR.recognizeDetailed）。
    static func makeTensor(
        _ imageData: Data,
        flipVertically: Bool = false
    ) throws -> (data: NSMutableData, shape: [NSNumber]) {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw KSError.api("验证码图片解码失败")
        }

        let srcW = cgImage.width
        let srcH = cgImage.height
        guard srcW > 0, srcH > 0 else { throw KSError.api("验证码图片尺寸异常") }
        let dstW = max(1, Int(Double(srcW) * Double(targetHeight) / Double(srcH)))

        // 1) 解码到 RGBA8 缓冲
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: srcW * srcH * 4)
        defer { pixels.deallocate() }
        pixels.initialize(repeating: 0, count: srcW * srcH * 4)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: pixels,
            width: srcW,
            height: srcH,
            bitsPerComponent: 8,
            bytesPerRow: srcW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw KSError.api("创建图像上下文失败")
        }

        // 先铺白底，避免透明像素被合成成黑色（PIL convert('L') 对透明图同样偏白）
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: srcW, height: srcH))
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))

        // 2) 灰度：L = (R*299 + G*587 + B*114) / 1000
        var gray = [Float](repeating: 0, count: srcW * srcH)
        for i in 0..<(srcW * srcH) {
            let r = Float(pixels[i * 4])
            let g = Float(pixels[i * 4 + 1])
            let b = Float(pixels[i * 4 + 2])
            gray[i] = (r * 299 + g * 587 + b * 114) / 1000
        }

        // 2.5) 仅在兜底尝试时原地做一次上下镜像（交换整行）
        if flipVertically {
            var y = 0
            while y < srcH / 2 {
                let a = y * srcW
                let b = (srcH - 1 - y) * srcW
                for x in 0..<srcW {
                    gray.swapAt(a + x, b + x)
                }
                y += 1
            }
        }

        // 3) 面积平均降采样（与安卓 CaptchaOcr.preprocess 的加权逻辑逐行对齐）
        var output = [Float](repeating: 0, count: targetHeight * dstW)
        let scaleY = Double(srcH) / Double(targetHeight)
        let scaleX = Double(srcW) / Double(dstW)

        for y in 0..<targetHeight {
            let sy0 = Double(y) * scaleY
            let sy1 = Double(y + 1) * scaleY
            let yy0 = Int(sy0)
            let yy1 = min(Int(sy1) + 1, srcH)

            for x in 0..<dstW {
                let sx0 = Double(x) * scaleX
                let sx1 = Double(x + 1) * scaleX
                let xx0 = Int(sx0)
                let xx1 = min(Int(sx1) + 1, srcW)
                var sum = 0.0
                var weight = 0.0

                guard yy0 < yy1, xx0 < xx1 else { continue }
                for yy in yy0..<yy1 {
                    let wy: Double
                    if Double(yy) < sy0 {
                        wy = max(0, Double(yy + 1) - sy0)
                    } else if Double(yy + 1) > sy1 {
                        wy = max(0, sy1 - Double(yy))
                    } else {
                        wy = 1
                    }
                    if wy <= 0 { continue }

                    for xx in xx0..<xx1 {
                        let wx: Double
                        if Double(xx) < sx0 {
                            wx = max(0, Double(xx + 1) - sx0)
                        } else if Double(xx + 1) > sx1 {
                            wx = max(0, sx1 - Double(xx))
                        } else {
                            wx = 1
                        }
                        if wx <= 0 { continue }
                        let w = wx * wy
                        sum += Double(gray[yy * srcW + xx]) * w
                        weight += w
                    }
                }
                output[y * dstW + x] = Float((weight > 0 ? sum / weight : 0) / 255.0)
            }
        }

        // 4) 打包成 ORT 输入
        let buffer = NSMutableData()
        output.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                buffer.append(base, length: raw.count)
            }
        }
        return (buffer, [1, 1, targetHeight, dstW] as [NSNumber])
    }
}

// MARK: - OCR：ONNX Runtime + CTC 解码

/// 完整复刻 ddddocr 的 common_old.onnx 推理流程：
/// 输入 (1,1,64,W) → 输出 (seq,1,8210) 或 (1,seq,8210) → argmax
/// → CTC 解码（去连续重复 + 去空白索引 0）→ charset.json 映射 → 只留字母数字。
final class CaptchaOCR {

    private let env: ORTEnv
    private let session: ORTSession
    private let charset: [String]
    private let inputName: String
    private let outputName: String

    init() throws {
        guard let modelURL = BundleResource.url("common_old", "onnx") else {
            throw KSError.missingResource("common_old.onnx")
        }
        guard let charsetURL = BundleResource.url("charset", "json") else {
            throw KSError.missingResource("charset.json")
        }

        let charsetData = try Data(contentsOf: charsetURL)
        guard let list = try JSONSerialization.jsonObject(with: charsetData) as? [String] else {
            throw KSError.api("charset.json 格式异常")
        }
        charset = list

        env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(2)
        try options.setGraphOptimizationLevel(.all)
        session = try ORTSession(
            env: env,
            modelPath: modelURL.path,
            sessionOptions: options
        )

        // 不写死输入输出名，直接从模型读取（不同 ddddocr 版本名字可能不同）
        let inputs = (try? session.inputNames()) ?? []
        let outputs = (try? session.outputNames()) ?? []
        inputName = inputs.first ?? "input"
        outputName = outputs.first ?? "output"
    }

    /// 一次推理结果：解码后的字符 + 置信度（各时间步最大值的均值，仅用于横向比较）
    struct Recognition {
        let code: String
        let score: Float
    }

    func recognize(_ imageData: Data) throws -> String {
        try recognizeDetailed(imageData).code
    }

    /// 主路径用正确行序推理；只有结果不是 4 位时才把图上下镜像再试一次，
    /// 两者中优先取 4 位、其次取置信度更高的那个。正常情况只推理一次。
    func recognizeDetailed(_ imageData: Data) throws -> Recognition {
        let primary = try infer(imageData, flipVertically: false)
        if primary.code.count == KiteSimCaptcha.length { return primary }

        let fallback = try infer(imageData, flipVertically: true)
        let candidates = [primary, fallback]
        if let best = candidates
            .filter({ $0.code.count == KiteSimCaptcha.length })
            .max(by: { $0.score < $1.score }) {
            return best
        }
        return candidates.max(by: { $0.score < $1.score }) ?? primary
    }

    private func infer(_ imageData: Data, flipVertically: Bool) throws -> Recognition {
        let tensor = try CaptchaPreprocessor.makeTensor(imageData, flipVertically: flipVertically)
        let input = try ORTValue(
            tensorData: tensor.data,
            elementType: .float,
            shape: tensor.shape
        )
        let results = try session.run(
            withInputs: [inputName: input],
            outputNames: Set([outputName]),
            runOptions: nil
        )
        guard let output = results[outputName] else {
            throw KSError.api("OCR 模型未返回输出 \(outputName)")
        }

        let info = try output.tensorTypeAndShapeInfo()
        let shape = info.shape.map { $0.intValue }
        guard let classes = shape.last, classes > 0 else {
            throw KSError.api("OCR 输出形状异常: \(shape)")
        }
        // (seq, 1, classes) 或 (1, seq, classes) 都按 seq*classes 连续内存读取
        let seqLen: Int
        if shape.count >= 3 {
            seqLen = shape[0] == 1 ? shape[1] : shape[0]
        } else {
            seqLen = shape[0]
        }

        let raw = try output.tensorData()
        let count = raw.length / MemoryLayout<Float>.stride
        let pointer = raw.bytes.assumingMemoryBound(to: Float.self)
        let probs = Array(UnsafeBufferPointer(start: pointer, count: count))

        var previous = -1
        var decoded = ""
        var scoreSum: Float = 0
        var scoreSteps = 0
        for step in 0..<seqLen {
            let start = step * classes
            if start + classes > probs.count { break }
            var best = 0
            var bestValue: Float = -Float.greatestFiniteMagnitude
            for c in 0..<classes {
                let v = probs[start + c]
                if v > bestValue {
                    bestValue = v
                    best = c
                }
            }
            scoreSum += bestValue
            scoreSteps += 1
            if best != previous, best != 0, best < charset.count {
                decoded.append(charset[best])
            }
            previous = best
        }

        // KiteSim 验证码只含字母数字。与安卓端一致：不做大小写转换。
        let digits: ClosedRange<UInt32> = 48...57
        let upper: ClosedRange<UInt32> = 65...90
        let lower: ClosedRange<UInt32> = 97...122
        let code = decoded.filter { ch in
            ch.unicodeScalars.count == 1 && ch.unicodeScalars.allSatisfy { scalar in
                digits.contains(scalar.value)
                    || upper.contains(scalar.value)
                    || lower.contains(scalar.value)
            }
        }
        return Recognition(code: code, score: scoreSteps > 0 ? scoreSum / Float(scoreSteps) : 0)
    }
}

/// 验证码固定 4 位（安卓端 Act 也是按 4 位判定的）
enum KiteSimCaptcha {
    static let length = 4
}

