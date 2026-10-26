import Foundation

struct ComicInfoMetadata {
    var title: String?
    var direction: ReadingDirection?
}

enum ComicInfoParser {
    static func parse(in root: URL) -> ComicInfoMetadata? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        var infoURL: URL?
        for case let url as URL in enumerator {
            if url.lastPathComponent.lowercased() == "comicinfo.xml" {
                infoURL = url
                break
            }
        }
        guard let infoURL, let data = try? Data(contentsOf: infoURL),
              let xml = String(data: data, encoding: .utf8) else { return nil }

        var meta = ComicInfoMetadata()
        meta.title = tag(xml, "Title")
        if let rtl = tag(xml, "Manga")?.lowercased() {
            // Yes / YesAndRightToLeft commonly means manga RTL
            if rtl.contains("yes") { meta.direction = .rtl }
            if rtl.contains("no") { meta.direction = .ltr }
        }
        if let reading = tag(xml, "ReadingDirection")?.lowercased() {
            if reading.contains("rtl") || reading.contains("right") { meta.direction = .rtl }
            if reading.contains("ltr") || reading.contains("left") { meta.direction = .ltr }
        }
        return meta
    }

    private static func tag(_ xml: String, _ name: String) -> String? {
        guard let open = xml.range(of: "<\(name)", options: .caseInsensitive) else { return nil }
        guard let gt = xml[open.upperBound...].firstIndex(of: ">") else { return nil }
        let start = xml.index(after: gt)
        guard let close = xml.range(of: "</\(name)>", options: .caseInsensitive, range: start..<xml.endIndex) else {
            return nil
        }
        return String(xml[start..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
