import AppKit
import CoreText
import Foundation

/// Esporta testo in PDF multipagina (report review).
enum ReviewPanelReportPDFExporter {
    enum ExportError: Error {
        case pdfContext
        case consumer
        case emptyDocument
    }

    static func writeMultipagePDF(text: String, destination: URL) throws {
        let pageWidth: CGFloat = 8.5 * 72.0
        let pageHeight: CGFloat = 11.0 * 72.0
        let margin: CGFloat = 48
        let frameRect = CGRect(
            x: margin,
            y: margin,
            width: pageWidth - 2 * margin,
            height: pageHeight - 2 * margin
        )

        let attr = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
                .foregroundColor: NSColor.textColor,
            ]
        )

        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        var range = CFRange(location: 0, length: 0)

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw ExportError.consumer
        }
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ExportError.pdfContext
        }

        var pageCount = 0
        while range.location < attr.length {
            ctx.beginPDFPage(nil)
            ctx.textMatrix = .identity
            ctx.translateBy(x: 0, y: pageHeight)
            ctx.scaleBy(x: 1, y: -1)

            let path = CGPath(rect: frameRect, transform: nil)
            range.length = attr.length - range.location
            let frameRef = CTFramesetterCreateFrame(framesetter, range, path, nil)
            CTFrameDraw(frameRef, ctx)

            let visible = CTFrameGetVisibleStringRange(frameRef)
            if visible.length == 0 {
                range.location += 1
            } else {
                range.location += visible.length
            }

            ctx.endPDFPage()
            pageCount += 1
            if pageCount > 10_000 { break }
        }

        ctx.closePDF()

        guard !data.isEmpty else { throw ExportError.emptyDocument }
        try data.write(to: destination, options: .atomic)
    }
}
