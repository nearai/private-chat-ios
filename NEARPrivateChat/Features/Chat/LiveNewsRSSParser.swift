import Foundation

final class BBCNewsRSSParser: NSObject, XMLParserDelegate {
    private(set) var items: [Item] = []

    private var isInsideItem = false
    private var currentElement: String?
    private var currentTitle = ""
    private var currentLink = ""

    struct Item {
        let title: String
        let link: String
    }

    func parse(data: Data) -> [Item] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse() ? items : []
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        if name == "item" {
            isInsideItem = true
            currentTitle = ""
            currentLink = ""
        }
        currentElement = isInsideItem ? name : nil
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if name == "item" {
            let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !link.isEmpty {
                items.append(Item(title: title, link: link))
            }
            isInsideItem = false
            currentElement = nil
            return
        }

        if currentElement == name {
            currentElement = nil
        }
    }

    private func append(_ string: String) {
        guard isInsideItem else { return }
        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        default:
            break
        }
    }
}
