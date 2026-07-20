import Foundation
import PDFKit
import UIKit
import Vision

#if canImport(FoundationModels)
import FoundationModels
#endif

struct LabImportBiomarkerDescriptor: Equatable, Sendable {
    let id: UUID
    let name: String
    let nameKey: String?
    let defaultUnit: String
    let typicalUnits: [String]

    @MainActor
    init(biomarker: HealthBiomarker) {
        id = biomarker.id
        name = biomarker.name
        nameKey = biomarker.nameKey
        defaultUnit = biomarker.defaultUnit
        typicalUnits = biomarker.typicalLabUnits
    }
}

struct ImportedLabResult: Equatable, Sendable {
    let biomarkerID: UUID
    var value: Decimal
    var unit: String
    var referenceLower: Decimal?
    var referenceUpper: Decimal?
    var notes: String?

    func labResult(id: UUID = UUID()) -> LabResult {
        LabResult(
            id: id,
            biomarkerID: biomarkerID,
            value: value,
            unit: unit,
            referenceLower: referenceLower,
            referenceUpper: referenceUpper,
            notes: notes
        )
    }
}

struct LabImportDraft: Equatable, Sendable {
    var collectedAt: Date
    var laboratory: String?
    var results: [ImportedLabResult]
    /// Local, app-owned copy of the document. It is carried through the
    /// review screen and only becomes attached to an analysis when saved.
    var importedPDFURL: URL? = nil
    var fileName: String
    let usedEmbeddedText: Bool
    let usedOCR: Bool
    let usedStructuredRecognition: Bool
    let usedFoundationModels: Bool
}

/// Keeps an app-owned copy of imported reports. A UIDocumentPicker URL may
/// stop being readable as soon as its security scope ends, while an analysis
/// must still be able to open its original PDF later.
enum LabPDFDocumentStore {
    private static let directoryName = "ImportedLabPDFs"

    static func persistCopy(of sourceURL: URL) throws -> URL {
        let manager = FileManager.default
        let directory = try storageDirectory(using: manager)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try manager.copyItem(at: sourceURL, to: destination)
        try manager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )

        guard manager.isReadableFile(atPath: destination.path) else {
            throw CocoaError(.fileReadNoPermission)
        }
        return destination
    }

    /// Store only the file name in the database. The absolute path of an app
    /// container can change after a restore or an app update, whereas the
    /// document directory is recreated at a stable location inside Wellnario.
    static func storageReference(for url: URL) -> String {
        url.lastPathComponent
    }

    static func url(for reference: String?) -> URL? {
        guard let reference = reference?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reference.isEmpty else {
            return nil
        }

        let manager = FileManager.default
        var candidates: [URL] = []
        if let fileURL = URL(string: reference), fileURL.isFileURL {
            candidates.append(fileURL.standardizedFileURL)
        }
        if reference.hasPrefix("/") {
            candidates.append(URL(fileURLWithPath: reference).standardizedFileURL)
        }

        let fileName = URL(fileURLWithPath: reference).lastPathComponent
        if !fileName.isEmpty {
            if let directory = try? storageDirectory(using: manager) {
                candidates.append(directory.appendingPathComponent(fileName, isDirectory: false))
            }
            if let legacyDirectory = try? legacyStorageDirectory(using: manager) {
                candidates.append(legacyDirectory.appendingPathComponent(fileName, isDirectory: false))
            }
        }

        return candidates.first {
            var isDirectory: ObjCBool = false
            return manager.fileExists(atPath: $0.path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
                && manager.isReadableFile(atPath: $0.path)
        }
    }

    static func isAvailable(at path: String?) -> Bool {
        url(for: path) != nil
    }

    private static func storageDirectory(using manager: FileManager) throws -> URL {
        let baseDirectory = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.wellnario.app"
        return baseDirectory
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Location used by the first PDF-import implementation. It remains a
    /// read-only fallback so reports already imported with that build keep
    /// opening after the storage-reference migration.
    private static func legacyStorageDirectory(using manager: FileManager) throws -> URL {
        let baseDirectory = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }
}

struct ExtractedLabDocument: Equatable, Sendable {
    let text: String
    let tableText: String
    let usedEmbeddedText: Bool
    let usedOCR: Bool
    let usedStructuredRecognition: Bool
}

enum LabPDFImportError: LocalizedError {
    case unreadablePDF
    case lockedPDF
    case noText
    case noFavoriteResults

    var errorDescription: String? {
        switch self {
        case .unreadablePDF:
            NSLocalizedString(
                "health.analytics.import.error.unreadable",
                comment: "The selected PDF could not be opened"
            )
        case .lockedPDF:
            NSLocalizedString(
                "health.analytics.import.error.locked",
                comment: "The selected PDF is protected"
            )
        case .noText:
            NSLocalizedString(
                "health.analytics.import.error.no_text",
                comment: "No readable text was found in the PDF"
            )
        case .noFavoriteResults:
            NSLocalizedString(
                "health.analytics.import.error.no_results",
                comment: "No favorite biomarker results were found"
            )
        }
    }
}

struct LabPDFImportService: Sendable {
    func importPDF(
        at url: URL,
        favoriteBiomarkers: [LabImportBiomarkerDescriptor]
    ) async throws -> LabImportDraft {
        let extraction = try await LabPDFTextExtractor.extract(
            from: url,
            customWords: favoriteBiomarkers.map(\.name)
        )
        var fallback = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: favoriteBiomarkers,
            fileName: url.lastPathComponent
        )
        fallback.importedPDFURL = url

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           SystemLanguageModel.default.availability == .available,
           let intelligentDraft = try? await FoundationLabInterpreter.interpret(
               extraction: extraction,
               favorites: favoriteBiomarkers,
               fileName: url.lastPathComponent,
               fallback: fallback
           ),
           !intelligentDraft.results.isEmpty {
            return intelligentDraft
        }
        #endif

        guard !fallback.results.isEmpty else {
            throw LabPDFImportError.noFavoriteResults
        }
        return fallback
    }
}

enum LabPDFTextExtractor {
    static func extract(
        from url: URL,
        customWords: [String]
    ) async throws -> ExtractedLabDocument {
        try await Task.detached(priority: .userInitiated) {
            try await extractOffMain(from: url, customWords: customWords)
        }.value
    }

    private static func extractOffMain(
        from url: URL,
        customWords: [String]
    ) async throws -> ExtractedLabDocument {
        guard let document = PDFDocument(url: url) else {
            throw LabPDFImportError.unreadablePDF
        }
        guard !document.isLocked else {
            throw LabPDFImportError.lockedPDF
        }

        var pageTexts: [String] = []
        var tableSections: [String] = []
        var usedEmbeddedText = false
        var usedOCR = false
        var usedStructuredRecognition = false

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let embeddedText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if containsMeaningfulText(embeddedText) {
                usedEmbeddedText = true
                pageTexts.append(pageHeader(pageIndex) + embeddedText)
                continue
            }

            guard let image = render(page: page) else { continue }
            usedOCR = true

            if #available(iOS 26.0, *),
               let structured = try? await recognizeStructuredDocument(
                   image: image,
                   customWords: customWords
               ),
               !structured.text.isEmpty {
                pageTexts.append(pageHeader(pageIndex) + structured.text)
                if !structured.tables.isEmpty {
                    tableSections.append(pageHeader(pageIndex) + structured.tables)
                    usedStructuredRecognition = true
                }
            } else {
                let recognized = try recognizeText(image: image, customWords: customWords)
                if !recognized.isEmpty {
                    pageTexts.append(pageHeader(pageIndex) + recognized)
                }
            }
        }

        let text = pageTexts.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw LabPDFImportError.noText
        }
        return ExtractedLabDocument(
            text: text,
            tableText: tableSections.joined(separator: "\n\n"),
            usedEmbeddedText: usedEmbeddedText,
            usedOCR: usedOCR,
            usedStructuredRecognition: usedStructuredRecognition
        )
    }

    private static func containsMeaningfulText(_ text: String) -> Bool {
        let alphanumericCount = text.unicodeScalars.reduce(into: 0) { count, scalar in
            if CharacterSet.alphanumerics.contains(scalar) { count += 1 }
        }
        return alphanumericCount >= 16
    }

    private static func pageHeader(_ zeroBasedPage: Int) -> String {
        "[Page \(zeroBasedPage + 1)]\n"
    }

    private static func render(page: PDFPage) -> CGImage? {
        let pageBounds = page.bounds(for: .cropBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else { return nil }
        let maximumDimension: CGFloat = 2_600
        let scale = min(4, maximumDimension / max(pageBounds.width, pageBounds.height))
        let targetSize = CGSize(
            width: max(1, floor(pageBounds.width * scale)),
            height: max(1, floor(pageBounds.height * scale))
        )
        return page.thumbnail(of: targetSize, for: .cropBox).cgImage
    }

    private static func recognizeText(
        image: CGImage,
        customWords: [String]
    ) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.customWords = customWords
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = (request.results ?? []).sorted { lhs, rhs in
            let verticalDifference = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if verticalDifference < 0.012 {
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }
        var rows: [[VNRecognizedTextObservation]] = []
        for observation in observations {
            if let lastRow = rows.last,
               let anchor = lastRow.first,
               abs(anchor.boundingBox.midY - observation.boundingBox.midY)
                   <= max(0.012, min(anchor.boundingBox.height, observation.boundingBox.height) * 0.5) {
                rows[rows.index(before: rows.endIndex)].append(observation)
            } else {
                rows.append([observation])
            }
        }
        return rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " | ")
        }
            .joined(separator: "\n")
    }

    @available(iOS 26.0, *)
    private static func recognizeStructuredDocument(
        image: CGImage,
        customWords: [String]
    ) async throws -> (text: String, tables: String) {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.customWords = customWords
        let observations = try await request.perform(on: image)
        let text = observations
            .map { $0.document.text.transcript }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let tables = observations.flatMap { observation in
            observation.document.tables.map { table in
                table.rows.map { row in
                    row.map { $0.content.text.transcript }
                        .joined(separator: " | ")
                }
                .joined(separator: "\n")
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        return (text, tables)
    }
}

enum LabDocumentResultParser {
    static func parse(
        extraction: ExtractedLabDocument,
        favorites: [LabImportBiomarkerDescriptor],
        fileName: String
    ) -> LabImportDraft {
        let source = [extraction.tableText, extraction.text]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        var resultByBiomarker: [UUID: ImportedLabResult] = [:]

        let lines = source.components(separatedBy: .newlines)
        for (lineIndex, line) in lines.enumerated() {
            guard let match = bestBiomarkerMatch(
                in: line,
                favorites: favorites,
                excluding: Set(resultByBiomarker.keys)
            ) else {
                continue
            }
            var rowFragments = [line]
            if decimalValues(in: textAfterMatchedAlias(line, alias: match.alias)).isEmpty {
                for followingIndex in (lineIndex + 1)..<min(lines.count, lineIndex + 5) {
                    let followingLine = lines[followingIndex]
                    if isExcludedAliasContext(
                        in: followingLine,
                        biomarker: match.biomarker
                    ) {
                        // PDFKit may emit the labels of adjacent table rows
                        // before their numeric columns. Ignore a related but
                        // distinct marker (for example free PSA) and continue
                        // looking for the current row's first numeric line.
                        continue
                    }
                    if bestBiomarkerMatch(in: followingLine, favorites: favorites) != nil {
                        break
                    }
                    rowFragments.append(followingLine)
                }
            } else if isConditionalReference(line) {
                for followingIndex in (lineIndex + 1)..<min(lines.count, lineIndex + 5) {
                    let followingLine = lines[followingIndex]
                    guard isReferenceContinuation(followingLine) else { break }
                    rowFragments.append(followingLine)
                }
            }
            guard let result = parseResult(
                from: rowFragments.joined(separator: " | "),
                biomarker: match.biomarker,
                matchedAlias: match.alias
            ) else {
                continue
            }
            resultByBiomarker[match.biomarker.id] = result
        }

        let orderedResults = favorites.compactMap { resultByBiomarker[$0.id] }
        return LabImportDraft(
            collectedAt: detectedDate(in: extraction.text) ?? Date(),
            laboratory: detectedLaboratory(in: extraction.text),
            results: orderedResults,
            fileName: fileName,
            usedEmbeddedText: extraction.usedEmbeddedText,
            usedOCR: extraction.usedOCR,
            usedStructuredRecognition: extraction.usedStructuredRecognition,
            usedFoundationModels: false
        )
    }

    private static func bestBiomarkerMatch(
        in line: String,
        favorites: [LabImportBiomarkerDescriptor],
        excluding excludedBiomarkerIDs: Set<UUID> = []
    ) -> (biomarker: LabImportBiomarkerDescriptor, alias: String)? {
        let normalizedLine = normalized(line)
        return favorites.compactMap { biomarker -> (LabImportBiomarkerDescriptor, String)? in
            guard !excludedBiomarkerIDs.contains(biomarker.id),
                  !isExcludedAliasContext(in: line, biomarker: biomarker) else {
                return nil
            }
            let matchingAlias = aliases(for: biomarker)
                .filter { aliasRange(of: $0, in: normalizedLine) != nil }
                .max { normalized($0).count < normalized($1).count }
            return matchingAlias.map { (biomarker, $0) }
        }
        .max { normalized($0.1).count < normalized($1.1).count }
    }

    private static func parseResult(
        from line: String,
        biomarker: LabImportBiomarkerDescriptor,
        matchedAlias: String
    ) -> ImportedLabResult? {
        let normalizedLine = normalized(line)
        guard let aliasRange = aliasRange(of: matchedAlias, in: normalizedLine) else {
            return nil
        }
        var tail = String(normalizedLine[aliasRange.upperBound...])

        let canonicalLine = canonicalUnit(normalizedLine)
        let detectedUnit = biomarker.typicalUnits
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
            .first { unit in canonicalLine.contains(canonicalUnit(unit)) }
        for unit in biomarker.typicalUnits where !unit.isEmpty {
            tail = tail.replacingOccurrences(of: normalized(unit), with: " ")
        }

        let numbers = decimalValues(in: tail)
        guard let value = numbers.first else { return nil }
        let reference = parsedReference(in: tailAfterFirstNumber(in: tail))

        return ImportedLabResult(
            biomarkerID: biomarker.id,
            value: value,
            unit: detectedUnit ?? biomarker.defaultUnit,
            referenceLower: reference.lower,
            referenceUpper: reference.upper,
            notes: reference.notes
        )
    }

    /// A biomarker name can itself include a number, as in "25-hidroxi
    /// vitamina D". That number is not the measured value, so use only the
    /// part following the matched name when deciding whether the result wraps
    /// onto the next PDF text line.
    private static func textAfterMatchedAlias(_ line: String, alias: String) -> String {
        let normalizedLine = normalized(line)
        guard let range = aliasRange(of: alias, in: normalizedLine) else { return line }
        return String(normalizedLine[range.upperBound...])
    }

    private static func parsedReference(
        in text: String
    ) -> (lower: Decimal?, upper: Decimal?, notes: String?) {
        let comparatorPattern = #"([<>≤≥])\s*([-+]?(?:\d+(?:[.,]\d+)?|[.,]\d+))"#
        let rangePattern = #"([-+]?(?:\d+(?:[.,]\d+)?|[.,]\d+))\s*[-–—]\s*([-+]?(?:\d+(?:[.,]\d+)?|[.,]\d+))"#
        let fullRange = NSRange(text.startIndex..., in: text)

        var lowerCandidates: [Decimal] = []
        var upperCandidates: [Decimal] = []
        var boundedCandidates: [(Decimal, Decimal)] = []

        if let regex = try? NSRegularExpression(pattern: comparatorPattern) {
            for match in regex.matches(in: text, range: fullRange) {
                guard match.numberOfRanges == 3,
                      let comparatorRange = Range(match.range(at: 1), in: text),
                      let valueRange = Range(match.range(at: 2), in: text),
                      let candidate = decimal(String(text[valueRange])) else {
                    continue
                }
                switch text[comparatorRange] {
                case "<", "≤":
                    if !upperCandidates.contains(candidate) {
                        upperCandidates.append(candidate)
                    }
                case ">", "≥":
                    if !lowerCandidates.contains(candidate) {
                        lowerCandidates.append(candidate)
                    }
                default:
                    break
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: rangePattern) {
            for match in regex.matches(in: text, range: fullRange) {
                guard match.numberOfRanges == 3,
                      let lowerRange = Range(match.range(at: 1), in: text),
                      let upperRange = Range(match.range(at: 2), in: text),
                      let lower = decimal(String(text[lowerRange])),
                      let upper = decimal(String(text[upperRange])) else {
                    continue
                }
                let candidate = (lower, upper)
                if !boundedCandidates.contains(where: { $0 == candidate }) {
                    boundedCandidates.append(candidate)
                }
            }
        }

        let hasCandidates = !lowerCandidates.isEmpty
            || !upperCandidates.isEmpty
            || !boundedCandidates.isEmpty
        guard hasCandidates else {
            return (nil, nil, nil)
        }

        let isConditional = isConditionalReference(text)

        var lower: Decimal?
        var upper: Decimal?
        let hasSingleBoundedRange = boundedCandidates.count == 1
            && lowerCandidates.isEmpty
            && upperCandidates.isEmpty
        let hasAtMostOneDirectionalBound = boundedCandidates.isEmpty
            && lowerCandidates.count <= 1
            && upperCandidates.count <= 1

        if !isConditional, hasSingleBoundedRange {
            lower = boundedCandidates[0].0
            upper = boundedCandidates[0].1
        } else if !isConditional, hasAtMostOneDirectionalBound {
            lower = lowerCandidates.first
            upper = upperCandidates.first
        } else {
            return (nil, nil, cleanedReferenceText(text))
        }

        if let lower, let upper, lower > upper {
            return (nil, nil, cleanedReferenceText(text))
        }
        return (lower, upper, nil)
    }

    private static func cleanedReferenceText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let whitespace = try? NSRegularExpression(pattern: #"\s+"#) else {
            return trimmed
        }
        return whitespace.stringByReplacingMatches(
            in: trimmed,
            range: range,
            withTemplate: " "
        )
    }

    private static func isConditionalReference(_ text: String) -> Bool {
        let normalizedText = normalized(text)
        let conditionalTokens = [
            "ayuno", "fasting", "non-fasting", "nonfasting",
            "hora", "hour", "riesgo", "risk", "segun", "according",
            "edad", "age", "sexo", "sex", "embarazo", "pregnan"
        ]
        return conditionalTokens.contains(where: normalizedText.contains)
    }

    private static func isReferenceContinuation(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["<", ">", "≤", "≥"].contains(where: trimmed.hasPrefix)
    }

    private static func decimalValues(in text: String) -> [Decimal] {
        let pattern = #"[-+]?(?:\d+(?:[.,]\d+)?|[.,]\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range, in: text) else { return nil }
            return decimal(String(text[valueRange]))
        }
    }

    private static func tailAfterFirstNumber(in text: String) -> String {
        let pattern = #"[-+]?(?:\d+(?:[.,]\d+)?|[.,]\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return text
        }
        return String(text[range.upperBound...])
    }

    static func decimal(_ text: String?) -> Decimal? {
        guard let text else { return nil }
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func canonicalUnit(_ text: String) -> String {
        var canonical = normalized(text)
            .filter { !$0.isWhitespace }
        canonical = canonical
            .replacingOccurrences(of: "10^3/", with: "10³/")
            .replacingOccurrences(of: "103/", with: "10³/")
            .replacingOccurrences(of: "10^9/", with: "10⁹/")
            .replacingOccurrences(of: "109/", with: "10⁹/")
            .replacingOccurrences(of: "/ul", with: "/µl")
        return canonical
    }

    private static func aliases(for biomarker: LabImportBiomarkerDescriptor) -> [String] {
        var values = [biomarker.name]
        switch biomarker.nameKey {
        case "health.biomarker.catalog.hemoglobin":
            values += ["Hemoglobina", "Hemoglobin", "HGB"]
        case "health.biomarker.catalog.hematocrit":
            values += ["Hematocrito", "Hematocrit", "HCT"]
        case "health.biomarker.catalog.leukocytes_blood":
            values += ["Leucocitos", "Leukocytes", "White blood cells", "WBC"]
        case "health.biomarker.catalog.platelets":
            values += ["Plaquetas", "Platelets", "PLT"]
        case "health.biomarker.catalog.glucose_blood":
            values += ["Glucosa", "Glucose", "Glucemia"]
        case "health.biomarker.catalog.creatinine":
            values += ["Creatinina", "Creatinine"]
        case "health.biomarker.catalog.cholesterol":
            values += ["Colesterol", "Colesterol total", "Total cholesterol"]
        case "health.biomarker.catalog.triglycerides":
            values += ["Triglicéridos", "Triglycerides"]
        case "health.biomarker.catalog.alt":
            values += ["ALT", "GPT", "Alanina aminotransferasa"]
        case "health.biomarker.catalog.tsh":
            values += ["TSH", "Tirotropina", "Thyrotropin"]
        case "health.biomarker.catalog.ph_urine":
            values += ["pH", "pH orina", "pH urinario", "Urine pH", "Urinary pH"]
        case "health.biomarker.catalog.specific_gravity":
            values += ["Densidad", "Densidad urinaria", "Specific gravity"]
        case "health.biomarker.catalog.protein_urine":
            values += ["Proteínas en orina", "Urine protein", "Proteinuria"]
        case "health.biomarker.catalog.glucose_urine":
            values += ["Glucosa en orina", "Urine glucose", "Glucosuria"]
        case "health.biomarker.catalog.leukocytes_urine":
            values += ["Leucocitos en orina", "Urine leukocytes"]
        case "health.biomarker.catalog.hdl":
            values += ["HDL", "Colesterol HDL"]
        case "health.biomarker.catalog.ldl":
            values += ["LDL", "Colesterol LDL"]
        case "health.biomarker.catalog.psa":
            values += ["PSA", "Antígeno prostático específico"]
        case "health.biomarker.catalog.crp":
            values += ["PCR", "CRP", "Proteína C reactiva"]
        case "health.biomarker.catalog.esr":
            values += ["VSG", "ESR", "Velocidad de sedimentación"]
        case "health.biomarker.catalog.ggt":
            values += ["GGT", "Gamma glutamil transferasa"]
        case "health.biomarker.catalog.albumin":
            values += ["Albúmina", "Albumin"]
        case "health.biomarker.catalog.ferritin":
            values += ["Ferritina", "Ferritin"]
        case "health.biomarker.catalog.cortisol":
            values += ["Cortisol"]
        case "health.biomarker.catalog.testosterone_total":
            values += ["Testosterona total", "Total testosterone"]
        case "health.biomarker.catalog.vitamin_d":
            values += [
                "Vitamina D", "Vitamin D", "25-OH vitamina D", "25 OH vitamina D",
                "25-hidroxi vitamina D", "25 hidroxi vitamina D",
                "25-hydroxy vitamin D", "25-hydroxyvitamin D", "Calcidiol"
            ]
        case "health.biomarker.catalog.glycated_hemoglobin":
            values += [
                "Hemoglobina glicosilada (HbA1c)", "Hemoglobina glicosilada HbA1c",
                "Hemoglobina glicosilada", "Hemoglobina glucosilada", "HbA1c", "A1C"
            ]
        case "health.biomarker.catalog.lymphocyte_percentage":
            values += [
                "Porcentaje de linfocitos", "Linfocitos %", "Linfocitos",
                "Lymphocyte percentage", "Lymphocytes %", "LYM%"
            ]
        case "health.biomarker.catalog.mcv":
            values += [
                "VCM", "MCV", "Volumen corpuscular medio", "Mean corpuscular volume"
            ]
        case "health.biomarker.catalog.rdw":
            values += [
                "RDW", "ADE", "Amplitud de distribución eritrocitaria",
                "Red cell distribution width"
            ]
        case "health.biomarker.catalog.alkaline_phosphatase":
            values += ["Fosfatasa alcalina", "Alkaline phosphatase", "ALP", "FA"]
        case "health.biomarker.catalog.bun":
            values += ["Nitrógeno ureico", "BUN", "Blood urea nitrogen"]
        case "health.biomarker.catalog.fev1":
            values += [
                "FEV1", "VEF1", "Volumen espiratorio forzado", "Forced expiratory volume"
            ]
        case "health.biomarker.catalog.systolic_blood_pressure":
            values += [
                "Presión arterial sistólica", "Tensión arterial sistólica",
                "Systolic blood pressure", "PAS", "SBP"
            ]
        case "health.biomarker.catalog.vo2_max":
            values += [
                "VO2 max", "VO₂ max", "VO2MAX", "VO₂MAX",
                "Consumo máximo de oxígeno", "Maximum oxygen uptake"
            ]
        default:
            break
        }
        return Array(Set(values.filter { !$0.isEmpty }))
    }

    private static func aliasRange(
        of alias: String,
        in normalizedLine: String
    ) -> Range<String.Index>? {
        let target = normalized(alias).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }

        var searchStart = normalizedLine.startIndex
        while searchStart < normalizedLine.endIndex,
              let candidate = normalizedLine.range(
                  of: target,
                  range: searchStart..<normalizedLine.endIndex
              ) {
            let hasValidLeadingBoundary: Bool
            if candidate.lowerBound == normalizedLine.startIndex {
                hasValidLeadingBoundary = true
            } else {
                let previous = normalizedLine[
                    normalizedLine.index(before: candidate.lowerBound)
                ]
                hasValidLeadingBoundary = !isAliasWordCharacter(previous)
            }

            let hasValidTrailingBoundary: Bool
            if candidate.upperBound == normalizedLine.endIndex {
                hasValidTrailingBoundary = true
            } else {
                let next = normalizedLine[candidate.upperBound]
                hasValidTrailingBoundary = !isAliasWordCharacter(next)
            }

            if hasValidLeadingBoundary, hasValidTrailingBoundary {
                return candidate
            }
            searchStart = candidate.upperBound
        }
        return nil
    }

    private static func isAliasWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func isExcludedAliasContext(
        in line: String,
        biomarker: LabImportBiomarkerDescriptor
    ) -> Bool {
        let normalizedLine = normalizedWords(line)
        switch biomarker.nameKey {
        case "health.biomarker.catalog.psa":
            let otherPSAMarkers = [
                "psa-fraccion libre", "psa fraccion libre", "psa libre",
                "free psa", "ratio psa", "psa-libre/psa-total"
            ]
            let isDifferentPSAMeasurement = otherPSAMarkers
                .map(normalizedWords)
                .contains(where: normalizedLine.contains)
            let explanatoryPrefixes = [
                "para valores de psa",
                "para niveles de psa",
                "si el valor de psa",
                "cuando el psa"
            ]
            return isDifferentPSAMeasurement
                || explanatoryPrefixes.contains(where: normalizedLine.hasPrefix)
        case "health.biomarker.catalog.cholesterol":
            let cholesterolFractions = [
                "colesterol hdl", "hdl colesterol",
                "colesterol ldl", "ldl colesterol",
                "colesterol vldl", "vldl colesterol",
                "cociente", "ratio"
            ]
            return cholesterolFractions.contains(where: normalizedLine.contains)
        case "health.biomarker.catalog.hdl",
             "health.biomarker.catalog.ldl":
            return normalizedLine.contains("cociente")
                || normalizedLine.contains("ratio")
        default:
            return false
        }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "μ", with: "µ")
            .lowercased()
    }

    private static func normalizedWords(_ text: String) -> String {
        normalized(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func detectedDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.date)
            .max()
    }

    private static func detectedLaboratory(in text: String) -> String? {
        let labels = ["laboratorio", "laboratory", "lab:"]
        for line in text.components(separatedBy: .newlines).prefix(30) {
            let folded = normalized(line)
            guard labels.contains(where: folded.contains) else { continue }
            if let separator = line.firstIndex(of: ":") {
                let value = line[line.index(after: separator)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count <= 100 { return value }
        }
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct GeneratedLabImport {
    @Guide(description: "Laboratory name exactly as written, or an empty string when absent.")
    var laboratory: String

    @Guide(description: "Collection date in YYYY-MM-DD format, or an empty string when absent.")
    var collectedDate: String

    @Guide(
        description: "Only results explicitly present in the document and included in the allowed biomarker list.",
        .maximumCount(50)
    )
    var results: [GeneratedLabResult]
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedLabResult {
    @Guide(description: "Exact UUID from the allowed biomarker list.")
    var biomarkerID: String

    @Guide(description: "Measured numeric value exactly as printed, using a dot as decimal separator.")
    var value: String

    @Guide(description: "Measurement unit exactly as printed, or the allowed default unit when absent.")
    var unit: String

    @Guide(description: "Explicit lower reference limit: the lower number of a simple range or the value after > or ≥. Empty when absent or conditional.")
    var referenceLower: String

    @Guide(description: "Explicit upper reference limit: the upper number of a simple range or the value after < or ≤. Empty when absent or conditional.")
    var referenceUpper: String

    @Guide(description: "A result flag or comment. Include conditional reference text here when limits depend on fasting, age, sex, risk or another unknown condition.")
    var notes: String
}

@available(iOS 26.0, *)
private enum FoundationLabInterpreter {
    static func interpret(
        extraction: ExtractedLabDocument,
        favorites: [LabImportBiomarkerDescriptor],
        fileName: String,
        fallback: LabImportDraft
    ) async throws -> LabImportDraft {
        let model = SystemLanguageModel.default
        let session = LanguageModelSession(
            model: model,
            instructions: """
            You extract laboratory test facts from OCR or embedded PDF text.
            Never diagnose, calculate, convert units, invent values, or infer reference ranges.
            The value after < or ≤ is an upper limit; the value after > or ≥ is a lower limit.
            Never use numbers from explanatory text, such as fasting hours, ages or dates, as limits.
            Expressions such as 10³/µL, 10^3/uL or extracted text such as 103/µL are units,
            never measured values or reference limits.
            Read each measured value and its reference range only from the same laboratory row.
            Never use a value from the preceding or following biomarker as a reference limit.
            PSA total, free PSA and the free-to-total PSA ratio are different measurements.
            When reference values depend on fasting, age, sex, risk or another unknown condition,
            leave both limits empty and preserve the complete conditional reference text in notes.
            Ignore every biomarker that is not in the allowed list.
            Return a result only when its measured value is explicitly present.
            """
        )
        let allowedBiomarkers = favorites.map { biomarker in
            let units = biomarker.typicalUnits
                .map { $0.isEmpty ? "(no unit)" : $0 }
                .joined(separator: ", ")
            return "\(biomarker.id.uuidString) | \(biomarker.name) | units: \(units)"
        }
        .joined(separator: "\n")
        let documentText = relevantText(
            extraction: extraction,
            favorites: favorites,
            maximumCharacters: 11_000
        )
        let prompt = """
        Extract the collection date, laboratory and matching results.

        ALLOWED FAVORITE BIOMARKERS
        \(allowedBiomarkers)

        DOCUMENT
        \(documentText)
        """
        let response = try await session.respond(to: prompt, generating: GeneratedLabImport.self)
        let generated = response.content
        let allowedByID = Dictionary(uniqueKeysWithValues: favorites.map { ($0.id, $0) })
        let fallbackByID = Dictionary(
            uniqueKeysWithValues: fallback.results.map { ($0.biomarkerID, $0) }
        )
        var generatedByID: [UUID: ImportedLabResult] = [:]

        for result in generated.results {
            guard let biomarkerID = UUID(uuidString: result.biomarkerID),
                  let biomarker = allowedByID[biomarkerID],
                  generatedByID[biomarkerID] == nil,
                  let generatedValue = LabDocumentResultParser.decimal(result.value) else {
                continue
            }
            let generatedUnit = result.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackResult = fallbackByID[biomarkerID]
            let value = fallbackResult?.value ?? generatedValue
            let canonicalGeneratedUnit = LabDocumentResultParser.canonicalUnit(generatedUnit)
            let supportedGeneratedUnit = biomarker.typicalUnits.first {
                LabDocumentResultParser.canonicalUnit($0) == canonicalGeneratedUnit
            }
            let unit = supportedGeneratedUnit
                ?? fallbackResult?.unit
                ?? biomarker.defaultUnit
            var lower = LabDocumentResultParser.decimal(result.referenceLower)
            var upper = LabDocumentResultParser.decimal(result.referenceUpper)
            var notes = nonEmpty(result.notes)
            if fallbackResult?.referenceLower == nil,
               fallbackResult?.referenceUpper == nil,
               let contextualReference = fallbackResult?.notes {
                lower = nil
                upper = nil
                notes = mergedNotes(notes, contextualReference)
            } else if let fallbackResult,
                      fallbackResult.referenceLower != nil
                        || fallbackResult.referenceUpper != nil {
                lower = fallbackResult.referenceLower
                upper = fallbackResult.referenceUpper
            } else if let parsedLower = lower,
                      let parsedUpper = upper,
                      parsedLower > parsedUpper {
                lower = nil
                upper = nil
            }
            generatedByID[biomarkerID] = ImportedLabResult(
                biomarkerID: biomarkerID,
                value: value,
                unit: unit,
                referenceLower: lower,
                referenceUpper: upper,
                notes: notes
            )
        }

        for fallbackResult in fallback.results
        where generatedByID[fallbackResult.biomarkerID] == nil {
            generatedByID[fallbackResult.biomarkerID] = fallbackResult
        }
        let orderedResults = favorites.compactMap { generatedByID[$0.id] }
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: generated.collectedDate)
            ?? fallback.collectedAt
        return LabImportDraft(
            collectedAt: min(date, Date()),
            laboratory: nonEmpty(generated.laboratory) ?? fallback.laboratory,
            results: orderedResults,
            importedPDFURL: fallback.importedPDFURL,
            fileName: fileName,
            usedEmbeddedText: extraction.usedEmbeddedText,
            usedOCR: extraction.usedOCR,
            usedStructuredRecognition: extraction.usedStructuredRecognition,
            usedFoundationModels: true
        )
    }

    private static func relevantText(
        extraction: ExtractedLabDocument,
        favorites: [LabImportBiomarkerDescriptor],
        maximumCharacters: Int
    ) -> String {
        let combined = [extraction.tableText, extraction.text]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard combined.count > maximumCharacters else { return combined }

        let nameTokens = favorites.flatMap {
            $0.name.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 }
        }
        let lines = combined.components(separatedBy: .newlines)
        var selectedIndices = IndexSet(integersIn: 0..<min(25, lines.count))
        for (index, line) in lines.enumerated() {
            let normalizedLine = line.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            .lowercased()
            if nameTokens.contains(where: normalizedLine.contains) {
                selectedIndices.insert(integersIn: max(0, index - 1)...min(lines.count - 1, index + 1))
            }
        }
        let selected = selectedIndices.map { lines[$0] }.joined(separator: "\n")
        return String(selected.prefix(maximumCharacters))
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func mergedNotes(_ first: String?, _ second: String) -> String {
        guard let first, first != second else { return second }
        return first + "\n" + second
    }
}
#endif
