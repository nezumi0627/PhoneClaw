import AVFoundation
import Contacts
import EventKit
import Foundation
import UIKit

// MARK: - ネイティブツール登録表
//
// 全てのネイティブ API ラッパーをここに集中登録する。
// SKILL.md は allowed-tools フィールドでツール名を参照する。

enum AppPermissionKind: String, CaseIterable, Identifiable {
    case microphone
    case calendar
    case reminders
    case contacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "マイク"
        case .calendar:   return "カレンダー"
        case .reminders:  return "リマインダー"
        case .contacts:   return "連絡先"
        }
    }

    var description: String {
        switch self {
        case .microphone: return "録音とリアルタイム音声入力を許可します"
        case .calendar:   return "カレンダーイベントの作成と書き込みを許可します"
        case .reminders:  return "リマインダーと ToDo の作成を許可します"
        case .contacts:   return "連絡先の照会、保存、削除を許可します"
        }
    }

    var icon: String {
        switch self {
        case .microphone: return "mic"
        case .calendar:   return "calendar"
        case .reminders:  return "bell"
        case .contacts:   return "person.crop.circle"
        }
    }
}

enum AppPermissionStatus: Equatable {
    case notDetermined
    case denied
    case restricted
    case granted

    var label: String {
        switch self {
        case .notDetermined: return "未リクエスト"
        case .denied:        return "拒否済み"
        case .restricted:    return "制限あり"
        case .granted:       return "許可済み"
        }
    }

    var detail: String {
        switch self {
        case .notDetermined: return "初回使用時にシステム許可ダイアログが表示されます"
        case .denied:        return "設定アプリから手動で許可を有効にしてください"
        case .restricted:    return "このデバイスでは権限が制限されています"
        case .granted:       return "関連スキルを直接実行できます"
        }
    }

    var isGranted: Bool { self == .granted }
}

struct RegisteredTool {
    let name: String
    let description: String
    let parameters: String
    let execute: ([String: Any]) async throws -> String
}

class ToolRegistry {
    static let shared = ToolRegistry()

    private var tools: [String: RegisteredTool] = [:]
    private let eventStore = EKEventStore()
    private let contactStore = CNContactStore()

    private init() {
        registerBuiltInTools()
    }

    // MARK: - 公開インターフェース

    func register(_ tool: RegisteredTool) {
        tools[tool.name] = tool
    }

    func find(name: String) -> RegisteredTool? {
        tools[name]
    }

    func execute(name: String, args: [String: Any]) async throws -> String {
        guard let tool = tools[name] else {
            return "{\"success\": false, \"error\": \"不明なツール: \(name)\"}"
        }
        return try await tool.execute(args)
    }

    /// SKILL.md の allowed-tools に対応するツールリストを取得
    func toolsFor(names: [String]) -> [RegisteredTool] {
        names.compactMap { tools[$0] }
    }

    /// ツール名が登録済みかどうか確認
    func hasToolNamed(_ name: String) -> Bool {
        tools[name] != nil
    }

    /// 登録済み全ツール名
    var allToolNames: [String] {
        Array(tools.keys).sorted()
    }

    func authorizationStatus(for kind: AppPermissionKind) -> AppPermissionStatus {
        switch kind {
        case .microphone:
            let permission: AVAudioSession.RecordPermission
            if #available(iOS 17.0, *) {
                permission = AVAudioApplication.shared.recordPermission
            } else {
                permission = AVAudioSession.sharedInstance().recordPermission
            }
            switch permission {
            case .granted:     return .granted
            case .denied:      return .denied
            case .undetermined: return .notDetermined
            @unknown default:  return .restricted
            }

        case .calendar:
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .fullAccess, .writeOnly, .authorized: return .granted
            case .notDetermined: return .notDetermined
            case .denied:        return .denied
            case .restricted:    return .restricted
            @unknown default:    return .restricted
            }

        case .reminders:
            let status = EKEventStore.authorizationStatus(for: .reminder)
            switch status {
            case .fullAccess, .authorized: return .granted
            case .notDetermined: return .notDetermined
            case .denied:        return .denied
            case .restricted, .writeOnly: return .restricted
            @unknown default:    return .restricted
            }

        case .contacts:
            let status = CNContactStore.authorizationStatus(for: .contacts)
            switch status {
            case .authorized: return .granted
            case .limited:    return .granted
            case .notDetermined: return .notDetermined
            case .denied:     return .denied
            case .restricted: return .restricted
            @unknown default: return .restricted
            }
        }
    }

    func allPermissionStatuses() -> [AppPermissionKind: AppPermissionStatus] {
        Dictionary(uniqueKeysWithValues: AppPermissionKind.allCases.map {
            ($0, authorizationStatus(for: $0))
        })
    }

    func requestAccess(for kind: AppPermissionKind) async throws -> Bool {
        switch kind {
        case .microphone: return try await requestMicrophoneAccess()
        case .calendar:   return try await requestCalendarWriteAccess()
        case .reminders:  return try await requestRemindersAccess()
        case .contacts:   return try await requestContactsAccess()
        }
    }

    private func requestMicrophoneAccess() async throws -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func requestCalendarWriteAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestWriteOnlyAccessToEvents { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    private func requestRemindersAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    private func requestContactsAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            contactStore.requestAccess(for: .contacts) { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    // ISO 8601 日時文字列を Date に変換
    private func parseISO8601Date(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isoFormatters: [ISO8601DateFormatter] = [
            {
                let f = ISO8601DateFormatter()
                f.timeZone = .current
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f
            }(),
            {
                let f = ISO8601DateFormatter()
                f.timeZone = .current
                f.formatOptions = [.withInternetDateTime]
                return f
            }()
        ]

        for formatter in isoFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }

        return nil
    }

    private func writableEventCalendar() -> EKCalendar? {
        if let calendar = eventStore.defaultCalendarForNewEvents,
           calendar.allowsContentModifications {
            return calendar
        }
        return eventStore.calendars(for: .event).first(where: \.allowsContentModifications)
    }

    private func writableReminderCalendar() -> EKCalendar? {
        if let calendar = eventStore.defaultCalendarForNewReminders(),
           calendar.allowsContentModifications {
            return calendar
        }
        return eventStore.calendars(for: .reminder).first(where: \.allowsContentModifications)
    }

    private func newReminderListTitle() -> String {
        "PhoneClaw リマインダー"
    }

    private func reminderCalendarCreationSources() -> [EKSource] {
        let existingReminderSources = Set(
            eventStore.calendars(for: .reminder).map(\.source.sourceIdentifier)
        )

        func priority(for source: EKSource) -> Int? {
            switch source.sourceType {
            case .local:       return existingReminderSources.contains(source.sourceIdentifier) ? 0 : 1
            case .mobileMe:    return existingReminderSources.contains(source.sourceIdentifier) ? 2 : 3
            case .calDAV:      return existingReminderSources.contains(source.sourceIdentifier) ? 4 : 5
            case .exchange:    return existingReminderSources.contains(source.sourceIdentifier) ? 6 : 7
            case .subscribed, .birthdays: return nil
            @unknown default:  return existingReminderSources.contains(source.sourceIdentifier) ? 8 : 9
            }
        }

        return eventStore.sources
            .compactMap { source -> (priority: Int, source: EKSource)? in
                guard let p = priority(for: source) else { return nil }
                return (p, source)
            }
            .sorted {
                $0.priority == $1.priority
                    ? $0.source.title.localizedCaseInsensitiveCompare($1.source.title) == .orderedAscending
                    : $0.priority < $1.priority
            }
            .map(\.source)
    }

    private func ensureWritableReminderCalendar() throws -> EKCalendar? {
        if let calendar = writableReminderCalendar() { return calendar }

        var lastError: Error?
        for source in reminderCalendarCreationSources() {
            let reminderList = EKCalendar(for: .reminder, eventStore: eventStore)
            reminderList.title = newReminderListTitle()
            reminderList.source = source

            do {
                try eventStore.saveCalendar(reminderList, commit: true)
                if reminderList.allowsContentModifications { return reminderList }
                if let saved = eventStore.calendar(withIdentifier: reminderList.calendarIdentifier),
                   saved.allowsContentModifications { return saved }
            } catch {
                lastError = error
            }
        }

        if let lastError { throw lastError }
        return nil
    }

    private func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func reminderDateComponents(from date: Date) -> DateComponents {
        Calendar.current.dateComponents(in: .current, from: date)
    }

    private func contactKeysToFetch() -> [CNKeyDescriptor] {
        [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
    }

    private func findExistingContact(phone: String) throws -> CNContact? {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let predicate = CNContact.predicateForContacts(
            matching: CNPhoneNumber(stringValue: trimmed)
        )
        return try contactStore.unifiedContacts(
            matching: predicate,
            keysToFetch: contactKeysToFetch()
        ).first
    }

    private func allContacts() throws -> [CNContact] {
        var contacts: [CNContact] = []
        let request = CNContactFetchRequest(keysToFetch: contactKeysToFetch())
        request.sortOrder = .userDefault
        try contactStore.enumerateContacts(with: request) { contact, _ in
            contacts.append(contact)
        }
        return contacts
    }

    private func formattedContactName(_ contact: CNContact) -> String {
        // 姓 + ミドルネーム + 名 の順で結合（日本式）
        let manual = [contact.familyName, contact.middleName, contact.givenName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined()
        if !manual.isEmpty { return manual }

        let nickname = contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nickname.isEmpty { return nickname }

        let organization = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !organization.isEmpty { return organization }

        return "名称未設定"
    }

    private func clipboardTextPreview(
        from text: String,
        maxCharacters: Int = 500
    ) -> (preview: String, truncated: Bool)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let endIndex = trimmed.index(
            trimmed.startIndex,
            offsetBy: maxCharacters,
            limitedBy: trimmed.endIndex
        ) ?? trimmed.endIndex

        return (
            preview: String(trimmed[..<endIndex]),
            truncated: endIndex < trimmed.endIndex
        )
    }

    private func contactSearchTexts(_ contact: CNContact) -> [String] {
        [
            formattedContactName(contact),
            contact.familyName,
            contact.middleName,
            contact.givenName,
            contact.nickname,
            contact.organizationName,
            contact.jobTitle
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    // 検索用エイリアス（敬称の除去など）
    private func relaxedSearchAliases(for raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var aliases = [trimmed]
        let suffixes = ["社長", "部長", "課長", "先生", "さん", "くん", "ちゃん", "氏"]
        for suffix in suffixes where trimmed.hasSuffix(suffix) {
            let candidate = String(trimmed.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.count >= 1 { aliases.append(candidate) }
        }

        return Array(NSOrderedSet(array: aliases)) as? [String] ?? aliases
    }

    private func primaryPhone(_ contact: CNContact) -> String? {
        contact.phoneNumbers
            .map { $0.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func primaryEmail(_ contact: CNContact) -> String? {
        contact.emailAddresses
            .map { String($0.value).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func contactSummaryDictionary(_ contact: CNContact) -> [String: Any] {
        [
            "identifier": contact.identifier,
            "name": formattedContactName(contact),
            "phone": primaryPhone(contact) ?? "",
            "company": contact.organizationName,
            "email": primaryEmail(contact) ?? ""
        ]
    }

    private func contactSummaryText(_ contact: CNContact) -> String {
        var parts = [formattedContactName(contact)]
        if let phone = primaryPhone(contact) { parts.append("電話 \(phone)") }
        if let email = primaryEmail(contact) { parts.append("メール \(email)") }
        let company = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !company.isEmpty { parts.append("会社 \(company)") }
        return parts.joined(separator: "、")
    }

    private func searchContacts(
        identifier: String? = nil,
        name: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        query: String? = nil
    ) throws -> [CNContact] {
        let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name  = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = phone?.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = query?.trimmingCharacters(in: .whitespacesAndNewlines)

        let candidates: [CNContact]
        if let identifier, !identifier.isEmpty {
            candidates = try contactStore.unifiedContacts(
                matching: CNContact.predicateForContacts(withIdentifiers: [identifier]),
                keysToFetch: contactKeysToFetch()
            )
        } else {
            candidates = try allContacts()
        }

        let matches = candidates.filter { contact in
            if let identifier, !identifier.isEmpty, contact.identifier != identifier { return false }

            if let name, !name.isEmpty {
                let aliases = relaxedSearchAliases(for: name)
                let searchTexts = contactSearchTexts(contact)
                let matched = aliases.contains { alias in
                    searchTexts.contains { $0.localizedCaseInsensitiveContains(alias) }
                }
                if !matched { return false }
            }

            if let phone, !phone.isEmpty,
               !contact.phoneNumbers.contains(where: {
                   $0.value.stringValue.localizedCaseInsensitiveContains(phone)
               }) { return false }

            if let email, !email.isEmpty,
               !contact.emailAddresses.contains(where: {
                   String($0.value).localizedCaseInsensitiveContains(email)
               }) { return false }

            if let query, !query.isEmpty {
                let aliases = relaxedSearchAliases(for: query)
                let textMatch = aliases.contains { alias in
                    contactSearchTexts(contact).contains {
                        $0.localizedCaseInsensitiveContains(alias)
                    }
                }
                let phoneMatch = contact.phoneNumbers.contains {
                    $0.value.stringValue.localizedCaseInsensitiveContains(query)
                }
                let emailMatch = contact.emailAddresses.contains {
                    String($0.value).localizedCaseInsensitiveContains(query)
                }
                if !(textMatch || phoneMatch || emailMatch) { return false }
            }

            return true
        }

        return matches.sorted {
            formattedContactName($0).localizedCaseInsensitiveCompare(formattedContactName($1)) == .orderedAscending
        }
    }

    // MARK: - 組み込みツール登録

    private func registerBuiltInTools() {
        func successPayload(result: String, extras: [String: Any] = [:]) -> String {
            var payload = extras
            payload["success"] = true
            payload["status"] = "succeeded"
            payload["result"] = result
            return jsonString(payload)
        }

        func failurePayload(error: String, extras: [String: Any] = [:]) -> String {
            var payload = extras
            payload["success"] = false
            payload["status"] = "failed"
            payload["error"] = error
            return jsonString(payload)
        }

        func officialDevicePayload() async -> [String: Any] {
            let info = ProcessInfo.processInfo
            let device = await MainActor.run {
                (
                    UIDevice.current.name,
                    UIDevice.current.model,
                    UIDevice.current.localizedModel,
                    UIDevice.current.systemName,
                    UIDevice.current.systemVersion,
                    UIDevice.current.identifierForVendor?.uuidString
                )
            }

            var payload: [String: Any] = [
                "success": true,
                "name": device.0,
                "model": device.1,
                "localized_model": device.2,
                "system_name": device.3,
                "system_version": device.4,
                "memory_bytes": Double(info.physicalMemory),
                "memory_gb": Double(info.physicalMemory) / 1_073_741_824.0,
                "processor_count": info.processorCount
            ]

            if let identifierForVendor = device.5, !identifierForVendor.isEmpty {
                payload["identifier_for_vendor"] = identifierForVendor
            }

            return payload
        }

        // ── クリップボード ──
        register(RegisteredTool(
            name: "clipboard-read",
            description: "クリップボードの現在の内容を読み取る",
            parameters: "なし"
        ) { _ in
            let snapshot = await MainActor.run { () -> [String: Any] in
                let pasteboard = UIPasteboard.general

                if pasteboard.numberOfItems == 0 { return ["kind": "empty"] }

                if pasteboard.hasImages {
                    return ["kind": "image", "item_count": pasteboard.numberOfItems]
                }

                if pasteboard.hasURLs,
                   let urlText = pasteboard.url?.absoluteString,
                   let preview = self.clipboardTextPreview(from: urlText, maxCharacters: 500) {
                    return ["kind": "url", "content": preview.preview, "truncated": preview.truncated]
                }

                if pasteboard.hasStrings,
                   let raw = pasteboard.string,
                   let preview = self.clipboardTextPreview(from: raw, maxCharacters: 500) {
                    return ["kind": "text", "content": preview.preview, "truncated": preview.truncated]
                }

                return ["kind": "unsupported", "item_count": pasteboard.numberOfItems]
            }

            switch snapshot["kind"] as? String {
            case "text":
                let preview = snapshot["content"] as? String ?? ""
                let truncated = snapshot["truncated"] as? Bool ?? false
                let suffix = truncated ? "（内容が長いため省略されました）" : ""
                return successPayload(
                    result: "クリップボードの内容：\(preview)\(suffix)",
                    extras: ["type": "text", "content": preview, "truncated": truncated]
                )

            case "url":
                let preview = snapshot["content"] as? String ?? ""
                let truncated = snapshot["truncated"] as? Bool ?? false
                let suffix = truncated ? "（内容が長いため省略されました）" : ""
                return successPayload(
                    result: "クリップボードはリンクです：\(preview)\(suffix)",
                    extras: ["type": "url", "content": preview, "truncated": truncated]
                )

            case "image":
                let itemCount = snapshot["item_count"] as? Int ?? 1
                return successPayload(
                    result: "クリップボードには画像が含まれています。メモリ節約のため直接デコードしません。",
                    extras: ["type": "image", "item_count": itemCount]
                )

            case "unsupported":
                let itemCount = snapshot["item_count"] as? Int ?? 1
                return successPayload(
                    result: "クリップボードには \(itemCount) 件の非テキストコンテンツが含まれています。",
                    extras: ["type": "unsupported", "item_count": itemCount]
                )

            default:
                return failurePayload(error: "クリップボードは空です")
            }
        })

        register(RegisteredTool(
            name: "clipboard-write",
            description: "テキストをクリップボードに書き込む",
            parameters: "text: コピーするテキスト内容"
        ) { args in
            guard let text = args["text"] as? String else {
                return failurePayload(error: "text パラメータがありません")
            }
            await MainActor.run { UIPasteboard.general.string = text }
            return successPayload(
                result: "\(text.count) 文字をクリップボードに書き込みました。",
                extras: ["copied_length": text.count]
            )
        })

        // ── デバイス ──
        register(RegisteredTool(
            name: "device-info",
            description: "iOS 公式 API でデバイス名、タイプ、システムバージョン、メモリ、プロセッサ数を一括取得",
            parameters: "なし"
        ) { _ in
            let payload = await officialDevicePayload()
            let name = payload["name"] as? String ?? ""
            let localizedModel = (payload["localized_model"] as? String)?.isEmpty == false
                ? (payload["localized_model"] as? String ?? "")
                : (payload["model"] as? String ?? "")
            let systemName = payload["system_name"] as? String ?? ""
            let systemVersion = payload["system_version"] as? String ?? ""
            let memoryGB = payload["memory_gb"] as? Double ?? 0
            let processorCount = payload["processor_count"] as? Int ?? 0

            let summary = [
                name.isEmpty ? nil : "デバイス名：\(name)",
                localizedModel.isEmpty ? nil : "デバイスタイプ：\(localizedModel)",
                systemVersion.isEmpty ? nil : "システムバージョン：\(systemName.isEmpty ? "" : systemName + " ")\(systemVersion)",
                memoryGB > 0 ? String(format: "物理メモリ：%.1f GB", memoryGB) : nil,
                processorCount > 0 ? "プロセッサコア数：\(processorCount)" : nil
            ].compactMap { $0 }.joined(separator: "\n")

            var enriched = payload
            enriched["result"] = summary
            enriched["status"] = "succeeded"
            return jsonString(enriched)
        })

        register(RegisteredTool(
            name: "device-name",
            description: "UIDevice.current.name でデバイス名を取得",
            parameters: "なし"
        ) { _ in
            let payload = await officialDevicePayload()
            let name = payload["name"] as? String ?? ""
            return successPayload(result: "このデバイスの名前は \(name) です。", extras: ["name": name])
        })

        register(RegisteredTool(
            name: "device-model",
            description: "UIDevice.current.model と localizedModel でデバイスタイプを取得",
            parameters: "なし"
        ) { _ in
            let payload = await officialDevicePayload()
            let model = payload["model"] as? String ?? ""
            let localizedModel = payload["localized_model"] as? String ?? ""
            return jsonString([
                "success": true,
                "status": "succeeded",
                "result": "このデバイスの公式タイプは \((localizedModel.isEmpty ? model : localizedModel)) です。",
                "model": model,
                "localized_model": localizedModel
            ])
        })

        register(RegisteredTool(
            name: "device-system-version",
            description: "UIDevice.current.systemName と systemVersion でシステムバージョンを取得",
            parameters: "なし"
        ) { _ in
            let payload = await officialDevicePayload()
            let systemName = payload["system_name"] as? String ?? ""
            let systemVersion = payload["system_version"] as? String ?? ""
            return jsonString([
                "success": true,
                "status": "succeeded",
                "result": "現在のシステムバージョンは \(systemName) \(systemVersion) です。",
                "system_name": systemName,
                "system_version": systemVersion
            ])
        })

        register(RegisteredTool(
            name: "device-memory",
            description: "ProcessInfo.processInfo.physicalMemory で物理メモリを取得",
            parameters: "なし"
        ) { _ in
            let payload = await officialDevicePayload()
            let memoryBytes = payload["memory_bytes"] as? Double ?? 0
            let memoryGB = payload["memory_gb"] as? Double ?? 0
            return jsonString([
                "success": true,
                "status": "succeeded",
                "result": String(format: "このデバイスの物理メモリは約 %.1f GB です。", memoryGB),
                "memory_bytes": memoryBytes,
                "memory_gb": memoryGB
            ])
        })

        register(RegisteredTool(
            name: "device-processor-count",
            description: "ProcessInfo.processInfo.processorCount でプロセッサコア数を取得",
            parameters: "なし"
        ) { _ in
            let payload = await officialDevicePayload()
            let processorCount = payload["processor_count"] as? Int ?? 0
            return jsonString([
                "success": true,
                "status": "succeeded",
                "result": "このデバイスのプロセッサコア数は \(processorCount) です。",
                "processor_count": processorCount
            ])
        })

        register(RegisteredTool(
            name: "device-identifier-for-vendor",
            description: "UIDevice.current.identifierForVendor で vendor 識別子を取得",
            parameters: "なし"
        ) { _ in
            let payload = await officialDevicePayload()
            let identifier = payload["identifier_for_vendor"] as? String ?? ""
            return jsonString([
                "success": true,
                "status": "succeeded",
                "result": "このデバイスの identifierForVendor は \(identifier) です。",
                "identifier_for_vendor": identifier
            ])
        })

        // ── テキスト ──
        register(RegisteredTool(
            name: "calculate-hash",
            description: "テキストのハッシュ値を計算",
            parameters: "text: ハッシュを計算するテキスト"
        ) { args in
            guard let text = args["text"] as? String else {
                return failurePayload(error: "text パラメータがありません")
            }
            let hash = text.hashValue
            return successPayload(
                result: "「\(text)」のハッシュ値は \(hash) です。",
                extras: ["input": text, "hash": hash]
            )
        })

        register(RegisteredTool(
            name: "text-reverse",
            description: "テキストを反転",
            parameters: "text: 反転するテキスト"
        ) { args in
            guard let text = args["text"] as? String else {
                return failurePayload(error: "text パラメータがありません")
            }
            let reversed = String(text.reversed())
            return successPayload(
                result: "反転結果：\(reversed)",
                extras: ["original": text, "reversed": reversed]
            )
        })

        // ── カレンダー / リマインダー / 連絡先 ──
        register(RegisteredTool(
            name: "calendar-create-event",
            description: "新しいカレンダーイベントを作成（タイトル、開始時刻、終了時刻、場所、メモ）",
            parameters: "title: イベントタイトル, start: ISO 8601 開始時刻, end: ISO 8601 終了時刻（任意）, location: 場所（任意）, notes: メモ（任意）"
        ) { args in
            guard let rawTitle = args["title"] as? String else {
                return failurePayload(error: "title パラメータがありません")
            }
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return failurePayload(error: "title パラメータがありません") }

            guard let startRaw = args["start"] as? String,
                  let startDate = self.parseISO8601Date(startRaw) else {
                return failurePayload(error: "有効な start パラメータがありません。ISO 8601 形式の時刻文字列が必要です")
            }

            let endRaw = (args["end"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let endDate = endRaw.flatMap(self.parseISO8601Date) ?? startDate.addingTimeInterval(3600)
            guard endDate >= startDate else {
                return failurePayload(error: "end は start より後でなければなりません")
            }

            let location = (args["location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = (args["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                guard try await self.requestCalendarWriteAccess() else {
                    return failurePayload(error: "カレンダーへの書き込み権限がありません")
                }

                guard let calendar = self.writableEventCalendar() else {
                    return failurePayload(error: "書き込み可能なカレンダーがありません。システムのカレンダーアプリで有効なカレンダーを作成してください")
                }

                let event = EKEvent(eventStore: self.eventStore)
                event.calendar = calendar
                event.title = title
                event.startDate = startDate
                event.endDate = endDate
                if let location, !location.isEmpty { event.location = location }
                if let notes, !notes.isEmpty { event.notes = notes }

                try self.eventStore.save(event, span: .thisEvent, commit: true)

                return successPayload(
                    result: "カレンダーに「\(title)」を作成しました。開始時刻：\(self.iso8601String(from: startDate))。",
                    extras: [
                        "eventId": event.eventIdentifier ?? "",
                        "title": title,
                        "start": self.iso8601String(from: startDate),
                        "end": self.iso8601String(from: endDate),
                        "location": location ?? "",
                        "notes": notes ?? ""
                    ]
                )
            } catch {
                return failurePayload(error: "カレンダーイベントの作成に失敗しました：\(error.localizedDescription)")
            }
        })

        register(RegisteredTool(
            name: "reminders-create",
            description: "新しいリマインダーを作成（タイトル、期限、メモ）",
            parameters: "title: リマインダータイトル, due: ISO 8601 期限（任意）, notes: メモ（任意）"
        ) { args in
            guard let rawTitle = args["title"] as? String else {
                return failurePayload(error: "title パラメータがありません")
            }
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return failurePayload(error: "title パラメータがありません") }

            let dueRaw = (args["due"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let dueRaw, !dueRaw.isEmpty, self.parseISO8601Date(dueRaw) == nil {
                return failurePayload(error: "due は有効な ISO 8601 形式の時刻文字列でなければなりません")
            }

            let dueDate = dueRaw.flatMap(self.parseISO8601Date)
            let notes = (args["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                guard try await self.requestRemindersAccess() else {
                    return failurePayload(error: "リマインダーへのアクセス権限がありません")
                }

                guard let calendar = try self.ensureWritableReminderCalendar() else {
                    return failurePayload(error: "書き込み可能なリマインダーリストがありません。リマインダーアプリでリストを作成してください")
                }

                let reminder = EKReminder(eventStore: self.eventStore)
                reminder.calendar = calendar
                reminder.title = title
                if let dueDate {
                    reminder.dueDateComponents = self.reminderDateComponents(from: dueDate)
                    reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
                }
                if let notes, !notes.isEmpty { reminder.notes = notes }

                try self.eventStore.save(reminder, commit: true)

                return successPayload(
                    result: dueDate != nil
                        ? "リマインダー「\(title)」を作成しました。リマインド時刻：\(self.iso8601String(from: dueDate!))。"
                        : "リマインダー「\(title)」を作成しました。",
                    extras: [
                        "calendarItemId": reminder.calendarItemIdentifier,
                        "title": title,
                        "due": dueDate.map { self.iso8601String(from: $0) } ?? "",
                        "notes": notes ?? ""
                    ]
                )
            } catch {
                return failurePayload(error: "リマインダーの作成に失敗しました：\(error.localizedDescription)")
            }
        })

        register(RegisteredTool(
            name: "contacts-upsert",
            description: "連絡先を作成または更新（電話番号が提供された場合は電話番号で重複チェック）",
            parameters: "name: 連絡先名, phone: 電話番号（任意）, company: 会社名（任意）, email: メール（任意）, notes: メモ（任意）"
        ) { args in
            guard let rawName = args["name"] as? String else {
                return failurePayload(error: "name パラメータがありません")
            }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return failurePayload(error: "name パラメータがありません") }

            let phone   = (args["phone"]   as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let company = (args["company"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let email   = (args["email"]   as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes   = (args["notes"]   as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            do {
                guard try await self.requestContactsAccess() else {
                    return failurePayload(error: "連絡先へのアクセス権限がありません")
                }

                let existingContact = phone.flatMap { try? self.findExistingContact(phone: $0) }
                let mutableContact: CNMutableContact
                let action: String

                if let existingContact {
                    mutableContact = existingContact.mutableCopy() as! CNMutableContact
                    action = "updated"
                } else {
                    mutableContact = CNMutableContact()
                    action = "created"
                }

                mutableContact.givenName = name
                mutableContact.familyName = ""

                if let phone, !phone.isEmpty {
                    mutableContact.phoneNumbers = [
                        CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))
                    ]
                }
                if let company, !company.isEmpty { mutableContact.organizationName = company }
                if let email, !email.isEmpty {
                    mutableContact.emailAddresses = [
                        CNLabeledValue(label: CNLabelWork, value: email as NSString)
                    ]
                }
                if let notes, !notes.isEmpty { mutableContact.note = notes }

                let saveRequest = CNSaveRequest()
                if existingContact != nil { saveRequest.update(mutableContact) }
                else { saveRequest.add(mutableContact, toContainerWithIdentifier: nil) }
                try self.contactStore.execute(saveRequest)

                let actionText = action == "updated" ? "更新" : "作成"
                return successPayload(
                    result: "連絡先「\(name)」を\(actionText)しました。",
                    extras: [
                        "action": action,
                        "name": name,
                        "phone": phone ?? "",
                        "company": company ?? "",
                        "email": email ?? "",
                        "notes": notes ?? ""
                    ]
                )
            } catch {
                return failurePayload(error: "連絡先の保存に失敗しました：\(error.localizedDescription)")
            }
        })

        register(RegisteredTool(
            name: "contacts-search",
            description: "連絡先を検索（名前、電話番号、メール、識別子、またはキーワードで照会）",
            parameters: "query: 検索キーワード（任意）, identifier: 連絡先識別子（任意）, name: 名前（任意）, phone: 電話番号（任意）, email: メール（任意）"
        ) { args in
            let identifier = (args["identifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name  = (args["name"]  as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = (args["phone"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = (args["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            guard identifier?.isEmpty == false
                || name?.isEmpty == false
                || phone?.isEmpty == false
                || email?.isEmpty == false
                || query?.isEmpty == false else {
                return failurePayload(error: "query、name、phone、email、identifier のいずれかを指定してください")
            }

            do {
                guard try await self.requestContactsAccess() else {
                    return failurePayload(error: "連絡先へのアクセス権限がありません")
                }

                let matches = Array(try self.searchContacts(
                    identifier: identifier, name: name, phone: phone, email: email, query: query
                ).prefix(5))

                let items = matches.map(self.contactSummaryDictionary)
                if matches.isEmpty {
                    return successPayload(result: "一致する連絡先が見つかりませんでした。", extras: ["count": 0, "items": items])
                }

                let lines = matches.map(self.contactSummaryText)
                return successPayload(
                    result: "\(matches.count) 件の連絡先が見つかりました：\(lines.joined(separator: "；"))。",
                    extras: ["count": matches.count, "items": items]
                )
            } catch {
                return failurePayload(error: "連絡先の検索に失敗しました：\(error.localizedDescription)")
            }
        })

        register(RegisteredTool(
            name: "contacts-delete",
            description: "連絡先を削除（名前、電話番号、メール、識別子、またはキーワードでマッチング後削除）",
            parameters: "query: 検索キーワード（任意）, identifier: 連絡先識別子（任意）, name: 名前（任意）, phone: 電話番号（任意）, email: メール（任意）"
        ) { args in
            let identifier = (args["identifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawName = (args["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = (args["phone"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = (args["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = rawName?
                .replacingOccurrences(of: "の電話番号", with: "")
                .replacingOccurrences(of: "電話番号", with: "")
                .replacingOccurrences(of: "携帯番号", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "、。,？！!? "))

            guard identifier?.isEmpty == false
                || name?.isEmpty == false
                || phone?.isEmpty == false
                || email?.isEmpty == false
                || query?.isEmpty == false else {
                return failurePayload(error: "query、name、phone、email、identifier のいずれかを指定してください")
            }

            do {
                guard try await self.requestContactsAccess() else {
                    return failurePayload(error: "連絡先へのアクセス権限がありません")
                }

                let matches = try self.searchContacts(
                    identifier: identifier, name: name, phone: phone, email: email, query: query
                )

                if matches.isEmpty {
                    return failurePayload(error: "一致する連絡先が見つかりませんでした")
                }

                if matches.count > 1 {
                    let previews = matches.prefix(5).map(self.contactSummaryText).joined(separator: "；")
                    return failurePayload(error: "複数の連絡先がマッチしました。より具体的な情報を入力してください：\(previews)")
                }

                let contact = matches[0]
                let mutableContact = contact.mutableCopy() as! CNMutableContact
                let saveRequest = CNSaveRequest()
                saveRequest.delete(mutableContact)
                try self.contactStore.execute(saveRequest)

                return successPayload(
                    result: "連絡先「\(self.formattedContactName(contact))」を削除しました。",
                    extras: [
                        "identifier": contact.identifier,
                        "name": self.formattedContactName(contact),
                        "phone": self.primaryPhone(contact) ?? "",
                        "email": self.primaryEmail(contact) ?? ""
                    ]
                )
            } catch {
                return failurePayload(error: "連絡先の削除に失敗しました：\(error.localizedDescription)")
            }
        })
    }
}

// MARK: - ヘルパー関数

func jsonEscape(_ str: String) -> String {
    str.replacingOccurrences(of: "\\", with: "\\\\")
       .replacingOccurrences(of: "\"", with: "\\\"")
       .replacingOccurrences(of: "\n", with: "\\n")
       .replacingOccurrences(of: "\t", with: "\\t")
}

func jsonString(_ object: Any) -> String {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object),
          let string = String(data: data, encoding: .utf8) else {
        return "{\"success\": false, \"error\": \"JSON エンコードに失敗しました\"}"
    }
    return string
}
