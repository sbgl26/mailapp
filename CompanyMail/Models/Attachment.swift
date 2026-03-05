import Foundation
import UniformTypeIdentifiers

struct Attachment: Identifiable, Hashable {
    let id: String
    var filename: String
    var mimeType: String
    var size: Int64
    var data: Data?
    var partID: String
    var isInline: Bool
    var contentId: String?

    init(
        filename: String,
        mimeType: String,
        size: Int64 = 0,
        data: Data? = nil,
        partID: String = "",
        isInline: Bool = false,
        contentId: String? = nil
    ) {
        self.id = UUID().uuidString
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.data = data
        self.partID = partID
        self.isInline = isInline
        self.contentId = contentId
    }

    var icon: String {
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType.hasPrefix("video/") { return "film" }
        if mimeType.hasPrefix("audio/") { return "music.note" }
        if mimeType.contains("pdf") { return "doc.richtext" }
        if mimeType.contains("zip") || mimeType.contains("compressed") { return "doc.zipper" }
        if mimeType.contains("spreadsheet") || mimeType.contains("excel") { return "tablecells" }
        if mimeType.contains("presentation") || mimeType.contains("powerpoint") { return "rectangle.on.rectangle" }
        if mimeType.contains("word") || mimeType.contains("document") { return "doc.text" }
        return "doc"
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var fileExtension: String {
        (filename as NSString).pathExtension
    }

    var utType: UTType? {
        UTType(mimeType: mimeType)
    }
}
