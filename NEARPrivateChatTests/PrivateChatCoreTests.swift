import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

@MainActor
final class PrivateChatCoreTests: XCTestCase {

    func makeMessage(
        id: String,
        role: ChatRole,
        text: String,
        model: String? = nil,
        createdAt: Date
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            text: text,
            model: model,
            createdAt: createdAt,
            status: "completed",
            responseID: id,
            isStreaming: false
        )
    }

    func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "NEARPrivateChatTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Unable to create isolated defaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    static func allKeys(in value: Any) -> Set<String> {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: Set(dictionary.keys)) { keys, element in
                keys.formUnion(allKeys(in: element.value))
            }
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { keys, element in
                keys.formUnion(allKeys(in: element))
            }
        }
        return []
    }
}

extension PrivateChatCoreTests {
    static func makeStoredZip(entries: [(String, String)]) -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var localOffsets: [(name: String, data: Data, offset: UInt32)] = []

        for (name, text) in entries {
            let nameData = Data(name.utf8)
            let fileData = Data(text.utf8)
            let localOffset = UInt32(archive.count)
            archive.appendLittleUInt32(0x0403_4b50)
            archive.appendLittleUInt16(20)
            archive.appendLittleUInt16(0)
            archive.appendLittleUInt16(0)
            archive.appendLittleUInt16(0)
            archive.appendLittleUInt16(0)
            archive.appendLittleUInt32(0)
            archive.appendLittleUInt32(UInt32(fileData.count))
            archive.appendLittleUInt32(UInt32(fileData.count))
            archive.appendLittleUInt16(UInt16(nameData.count))
            archive.appendLittleUInt16(0)
            archive.append(nameData)
            archive.append(fileData)
            localOffsets.append((name: name, data: fileData, offset: localOffset))
        }

        let centralOffset = UInt32(archive.count)
        for entry in localOffsets {
            let nameData = Data(entry.name.utf8)
            centralDirectory.appendLittleUInt32(0x0201_4b50)
            centralDirectory.appendLittleUInt16(20)
            centralDirectory.appendLittleUInt16(20)
            centralDirectory.appendLittleUInt16(0)
            centralDirectory.appendLittleUInt16(0)
            centralDirectory.appendLittleUInt16(0)
            centralDirectory.appendLittleUInt16(0)
            centralDirectory.appendLittleUInt32(0)
            centralDirectory.appendLittleUInt32(UInt32(entry.data.count))
            centralDirectory.appendLittleUInt32(UInt32(entry.data.count))
            centralDirectory.appendLittleUInt16(UInt16(nameData.count))
            centralDirectory.appendLittleUInt16(0)
            centralDirectory.appendLittleUInt16(0)
            centralDirectory.appendLittleUInt16(0)
            centralDirectory.appendLittleUInt16(0)
            centralDirectory.appendLittleUInt32(0)
            centralDirectory.appendLittleUInt32(entry.offset)
            centralDirectory.append(nameData)
        }
        archive.append(centralDirectory)
        archive.appendLittleUInt32(0x0605_4b50)
        archive.appendLittleUInt16(0)
        archive.appendLittleUInt16(0)
        archive.appendLittleUInt16(UInt16(entries.count))
        archive.appendLittleUInt16(UInt16(entries.count))
        archive.appendLittleUInt32(UInt32(centralDirectory.count))
        archive.appendLittleUInt32(centralOffset)
        archive.appendLittleUInt16(0)
        return archive
    }
}

extension Data {
    mutating func appendLittleUInt16(_ value: UInt16) {
        append(UInt8(value & 0x00ff))
        append(UInt8((value >> 8) & 0x00ff))
    }

    mutating func appendLittleUInt32(_ value: UInt32) {
        append(UInt8(value & 0x0000_00ff))
        append(UInt8((value >> 8) & 0x0000_00ff))
        append(UInt8((value >> 16) & 0x0000_00ff))
        append(UInt8((value >> 24) & 0x0000_00ff))
    }
}
