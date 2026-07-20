import UIKit
import XCTest
@testable import Wellnario

@MainActor
final class HealthDataStoreTests: XCTestCase {
    func testImportedPDFStoreKeepsAnAppOwnedCopyUsingAStableReference() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("sample report".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let copied = try LabPDFDocumentStore.persistCopy(of: source)
        defer { try? FileManager.default.removeItem(at: copied) }

        let reference = LabPDFDocumentStore.storageReference(for: copied)
        XCTAssertFalse(reference.contains("/"))
        XCTAssertEqual(LabPDFDocumentStore.url(for: reference)?.path, copied.path)

        try FileManager.default.removeItem(at: source)
        XCTAssertTrue(LabPDFDocumentStore.isAvailable(at: reference))
    }

    func testAnalysisCountsOnlyValuesOutsideConfiguredReferenceBounds() {
        let biomarkerID = UUID()
        let analysis = LabAnalysis(
            id: UUID(),
            collectedAt: Date(),
            laboratory: nil,
            notes: nil,
            results: [
                LabResult(
                    id: UUID(),
                    biomarkerID: biomarkerID,
                    value: 69,
                    unit: "mg/dL",
                    referenceLower: 70,
                    referenceUpper: 100
                ),
                LabResult(
                    id: UUID(),
                    biomarkerID: biomarkerID,
                    value: 101,
                    unit: "mg/dL",
                    referenceLower: 70,
                    referenceUpper: 100
                ),
                LabResult(
                    id: UUID(),
                    biomarkerID: biomarkerID,
                    value: 70,
                    unit: "mg/dL",
                    referenceLower: 70,
                    referenceUpper: 100
                ),
                LabResult(
                    id: UUID(),
                    biomarkerID: biomarkerID,
                    value: 100,
                    unit: "mg/dL",
                    referenceLower: 70,
                    referenceUpper: 100
                ),
                LabResult(
                    id: UUID(),
                    biomarkerID: biomarkerID,
                    value: 500,
                    unit: "mg/dL",
                    referenceLower: nil,
                    referenceUpper: nil
                )
            ]
        )

        XCTAssertEqual(analysis.outOfRangeResultCount, 2)
    }

    func testSeedsAllBiologicalAgeBiomarkersWithDistinctArtwork() throws {
        let (store, _) = try makeStore()
        let biomarkers = store.biomarkers()

        XCTAssertEqual(biomarkers.filter(\.isSeeded).count, 35)
        XCTAssertEqual(biomarkers.filter { $0.sampleType == .blood }.count, 27)
        XCTAssertEqual(biomarkers.filter { $0.sampleType == .urine }.count, 5)
        XCTAssertEqual(biomarkers.filter { $0.sampleType == .other }.count, 3)

        let imageKeys = biomarkers.compactMap(\.imageKey)
        XCTAssertEqual(Set(imageKeys).count, 35)
        for imageKey in imageKeys {
            XCTAssertNotNil(UIImage(named: imageKey), "Missing biomarker artwork: \(imageKey)")
        }
    }

    func testCustomBiomarkerAndFavoritePersist() throws {
        let (store, url) = try makeStore()
        let created = try store.createBiomarker(
            HealthBiomarkerDraft(
                name: "Vitamina D",
                sampleType: .blood,
                defaultUnit: "ng/mL"
            )
        )
        try store.setFavorite(true, biomarkerID: created.id)

        let reopened = try HealthDataStore(databaseURL: url)
        let persisted = try XCTUnwrap(reopened.biomarkers().first { $0.id == created.id })
        XCTAssertEqual(persisted.customName, "Vitamina D")
        XCTAssertEqual(persisted.sampleType, .blood)
        XCTAssertEqual(persisted.defaultUnit, "ng/mL")
        XCTAssertTrue(persisted.isFavorite)
    }

    func testAnalysisResultsPersistAndFeedBiomarkerHistory() throws {
        let (store, url) = try makeStore()
        let glucose = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.glucose_blood" }
        )
        let analysisID = UUID()
        let resultID = UUID()
        let date = Date(timeIntervalSince1970: 1_752_883_200)
        try store.saveAnalysis(
            LabAnalysis(
                id: analysisID,
                collectedAt: date,
                laboratory: "Laboratorio central",
                notes: "En ayunas",
                results: [
                    LabResult(
                        id: resultID,
                        biomarkerID: glucose.id,
                        value: 92.5,
                        unit: "mg/dL",
                        referenceLower: 70,
                        referenceUpper: 100,
                        notes: "Muestra en ayunas"
                    )
                ],
                importedPDFPath: "/private/var/mobile/Library/Application Support/ImportedLabPDFs/report.pdf",
                importedPDFName: "Resultados junio.pdf"
            )
        )

        let reopened = try HealthDataStore(databaseURL: url)
        let analysis = try XCTUnwrap(reopened.analyses().first { $0.id == analysisID })
        XCTAssertEqual(analysis.results.first?.value, 92.5)
        XCTAssertEqual(analysis.laboratory, "Laboratorio central")
        XCTAssertEqual(
            analysis.importedPDFPath,
            "/private/var/mobile/Library/Application Support/ImportedLabPDFs/report.pdf"
        )
        XCTAssertEqual(analysis.importedPDFName, "Resultados junio.pdf")
        let measurement = try XCTUnwrap(reopened.measurements(for: glucose.id).first)
        XCTAssertEqual(measurement.id, resultID)
        XCTAssertEqual(measurement.result.unit, "mg/dL")
        XCTAssertEqual(measurement.result.referenceLower, 70)
        XCTAssertEqual(measurement.result.referenceUpper, 100)
        XCTAssertEqual(measurement.result.notes, "Muestra en ayunas")
    }

    func testBiomarkerTrendsUsesLatestAnalysesAndHighlightsOutOfRangeFavorites() throws {
        let (store, _) = try makeStore()
        let glucose = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.glucose_blood" }
        )
        let urinePH = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.ph_urine" }
        )
        try store.setFavorite(true, biomarkerID: glucose.id)
        try store.setFavorite(true, biomarkerID: urinePH.id)

        let today = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        let analyses = [
            makeAnalysis(biomarkerID: glucose.id, value: 88, date: today.addingTimeInterval(-42 * 86_400)),
            makeAnalysis(biomarkerID: glucose.id, value: 99, date: today.addingTimeInterval(-28 * 86_400)),
            makeAnalysis(biomarkerID: glucose.id, value: 108, date: today.addingTimeInterval(-14 * 86_400)),
            makeAnalysis(biomarkerID: glucose.id, value: 94, date: today)
        ]
        for analysis in analyses { try store.saveAnalysis(analysis) }

        let suiteName = "WellnarioBiomarkerTrendsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let controller = BiomarkerTrendsViewController(store: store, defaults: defaults)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let chart = try XCTUnwrap(descendant(
            of: WellnessTrendChartView.self,
            identifier: "health.biomarker_trends.chart",
            in: controller.view
        ))
        XCTAssertEqual(chart.values.compactMap { $0 }, [88, 99, 108, 94])
        XCTAssertNotNil(chart.linearTrend)
        XCTAssertEqual(chart.referenceLine, .linearTrend)

        let periodSelector = try XCTUnwrap(descendant(
            of: UISegmentedControl.self,
            identifier: "health.biomarker_trends.period.selector",
            in: controller.view
        ))
        XCTAssertEqual(periodSelector.numberOfSegments, 2)
        XCTAssertEqual(periodSelector.selectedSegmentIndex, 1)
        let referenceSelector = try XCTUnwrap(descendant(
            of: UISegmentedControl.self,
            identifier: "health.biomarker_trends.reference.selector",
            in: controller.view
        ))
        XCTAssertEqual(referenceSelector.numberOfSegments, 2)

        let bloodSection = try XCTUnwrap(descendant(
            of: UILabel.self,
            identifier: "health.biomarker_trends.summary.section.blood",
            in: controller.view
        ))
        XCTAssertEqual(bloodSection.text, L10n.text("health.biomarkers.filter.blood"))
        let urineSection = try XCTUnwrap(descendant(
            of: UILabel.self,
            identifier: "health.biomarker_trends.summary.section.urine",
            in: controller.view
        ))
        XCTAssertEqual(urineSection.text, L10n.text("health.biomarkers.filter.urine"))

        let newestAnalysis = try XCTUnwrap(store.analyses().first)
        let newestValue = try XCTUnwrap(descendant(
            of: UILabel.self,
            identifier: "health.biomarker_trends.summary.result.\(glucose.id.uuidString).\(newestAnalysis.id.uuidString)",
            in: controller.view
        ))
        XCTAssertEqual(newestValue.text, "94")

        let fourthNewestAnalysis = try XCTUnwrap(store.analyses().dropFirst(3).first)
        XCTAssertNotNil(descendant(
            of: UILabel.self,
            identifier: "health.biomarker_trends.summary.result.\(glucose.id.uuidString).\(fourthNewestAnalysis.id.uuidString)",
            in: controller.view
        ))
        controller.view.layoutIfNeeded()
        let bloodTable = try XCTUnwrap(descendant(
            of: UIScrollView.self,
            identifier: "health.biomarker_trends.summary.table.blood",
            in: controller.view
        ))
        XCTAssertEqual(
            bloodTable.contentSize.width,
            CGFloat(store.analyses().count) * 46,
            accuracy: 0.5
        )
        let glucoseName = try XCTUnwrap(descendant(
            of: UILabel.self,
            identifier: "health.biomarker_trends.summary.name.\(glucose.id.uuidString)",
            in: controller.view
        ))
        XCTAssertFalse(glucoseName.isDescendant(of: bloodTable))
        let nameFrame = glucoseName.convert(glucoseName.bounds, to: controller.view)
        let tableFrame = bloodTable.convert(bloodTable.bounds, to: controller.view)
        XCTAssertEqual(tableFrame.minX - nameFrame.maxX, 2, accuracy: 0.5)
        let newestDateHeader = try XCTUnwrap(descendant(
            of: UILabel.self,
            identifier: "health.biomarker_trends.summary.date.\(newestAnalysis.id.uuidString)",
            in: controller.view
        ))
        XCTAssertEqual(newestDateHeader.text?.components(separatedBy: "\n").count, 2)

        let outsideAnalysis = try XCTUnwrap(store.analyses().first {
            $0.results.contains { $0.value == 108 }
        })
        let outsideValue = try XCTUnwrap(descendant(
            of: UILabel.self,
            identifier: "health.biomarker_trends.summary.result.\(glucose.id.uuidString).\(outsideAnalysis.id.uuidString)",
            in: controller.view
        ))
        XCTAssertTrue(outsideValue.textColor.isEqual(WellnarioPalette.danger))
    }

    func testBiomarkerHistoryPacksThreeAnalysisColumnsWithoutInternalGaps() throws {
        let (store, _) = try makeStore()
        let glucose = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.glucose_blood" }
        )
        try store.setFavorite(true, biomarkerID: glucose.id)

        let today = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        let analyses = [
            makeAnalysis(biomarkerID: glucose.id, value: 88, date: today.addingTimeInterval(-14 * 86_400)),
            makeAnalysis(biomarkerID: glucose.id, value: 99, date: today.addingTimeInterval(-7 * 86_400)),
            makeAnalysis(biomarkerID: glucose.id, value: 94, date: today)
        ]
        for analysis in analyses { try store.saveAnalysis(analysis) }

        let suiteName = "WellnarioBiomarkerHistoryLayoutTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let controller = BiomarkerTrendsViewController(store: store, defaults: defaults)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let table = try XCTUnwrap(descendant(
            of: UIScrollView.self,
            identifier: "health.biomarker_trends.summary.table.blood",
            in: controller.view
        ))
        let orderedAnalyses = store.analyses()
        let labels = try orderedAnalyses.map { analysis in
            try XCTUnwrap(descendant(
                of: UILabel.self,
                identifier: "health.biomarker_trends.summary.result.\(glucose.id.uuidString).\(analysis.id.uuidString)",
                in: table
            ))
        }
        let frames = labels.map { $0.convert($0.bounds, to: table) }
        XCTAssertEqual(frames[1].minX - frames[0].minX, 46, accuracy: 0.5)
        XCTAssertEqual(frames[2].minX - frames[1].minX, 46, accuracy: 0.5)
        frames.forEach { XCTAssertEqual($0.width, 46, accuracy: 0.5) }
        XCTAssertEqual(table.contentSize.width, 138, accuracy: 0.5)
    }

    func testTypicalLabUnitsUseBiomarkerSpecificAlternatives() throws {
        let (store, _) = try makeStore()
        let glucose = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.glucose_blood" }
        )
        let creatinine = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.creatinine" }
        )

        XCTAssertEqual(glucose.typicalLabUnits, ["mg/dL", "mmol/L"])
        XCTAssertEqual(creatinine.typicalLabUnits, ["mg/dL", "µmol/L"])
        let vitaminD = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.vitamin_d" }
        )
        let glycatedHemoglobin = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.glycated_hemoglobin" }
        )
        let alkalinePhosphatase = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.alkaline_phosphatase" }
        )
        let bun = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.bun" }
        )
        let fev1 = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.fev1" }
        )
        let vo2Max = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.vo2_max" }
        )
        XCTAssertEqual(vitaminD.typicalLabUnits, ["ng/mL", "nmol/L"])
        XCTAssertEqual(glycatedHemoglobin.typicalLabUnits, ["%", "mmol/mol"])
        XCTAssertEqual(alkalinePhosphatase.typicalLabUnits, ["U/L", "µkat/L"])
        XCTAssertEqual(bun.typicalLabUnits, ["mg/dL", "mmol/L"])
        XCTAssertEqual(fev1.typicalLabUnits, ["mL", "L"])
        XCTAssertEqual(vo2Max.typicalLabUnits, ["mL/kg/min"])
    }

    func testVO2MaxUsesAppleHealthAverageUntilThereIsARecentLaboratoryResult() throws {
        let (store, _) = try makeStore()
        let vo2Max = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.vo2_max" }
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 19,
            hour: 12
        )))
        let cutoff = try XCTUnwrap(calendar.date(byAdding: .year, value: -2, to: now))
        var snapshot = AppleHealthSnapshot.empty
        snapshot.vo2Max = AppleHealthMeasurement(
            value: 46.5,
            date: now,
            sourceName: "Apple Health"
        )

        let olderLaboratoryMeasurement = BiomarkerMeasurement(
            analysisID: UUID(),
            result: LabResult(
                id: UUID(),
                biomarkerID: vo2Max.id,
                value: 41,
                unit: "mL/kg/min",
                referenceLower: nil,
                referenceUpper: nil
            ),
            collectedAt: cutoff.addingTimeInterval(-1),
            laboratory: "Lab"
        )
        let fallback = BiomarkersViewController.displayValue(
            for: vo2Max,
            latestLaboratoryMeasurement: olderLaboratoryMeasurement,
            appleHealthSnapshot: snapshot,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(fallback?.source, .appleHealthVO2MaxThreeMonthAverage)
        XCTAssertEqual(fallback?.value, Decimal(46.5))
        XCTAssertEqual(fallback?.unit, "mL/kg/min")

        let recentLaboratoryMeasurement = BiomarkerMeasurement(
            analysisID: UUID(),
            result: LabResult(
                id: UUID(),
                biomarkerID: vo2Max.id,
                value: 44,
                unit: "mL/kg/min",
                referenceLower: nil,
                referenceUpper: nil
            ),
            collectedAt: cutoff.addingTimeInterval(1),
            laboratory: "Lab"
        )
        let laboratoryPriority = BiomarkersViewController.displayValue(
            for: vo2Max,
            latestLaboratoryMeasurement: recentLaboratoryMeasurement,
            appleHealthSnapshot: snapshot,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(laboratoryPriority?.source, .laboratory)
        XCTAssertEqual(laboratoryPriority?.value, 44)
    }

    func testImportedAnalysisShowsPDFButtonInList() throws {
        let (store, _) = try makeStore()
        let glucose = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.glucose_blood" }
        )
        var analysis = makeAnalysis(biomarkerID: glucose.id, value: 92, date: Date())
        analysis.importedPDFPath = "/private/var/mobile/ImportedLabPDFs/resultados.pdf"
        analysis.importedPDFName = "Resultados.pdf"
        try store.saveAnalysis(analysis)

        let controller = LabAnalysesViewController(store: store)
        controller.loadViewIfNeeded()
        let cell = controller.tableView(
            controller.tableView,
            cellForRowAt: IndexPath(row: 0, section: 0)
        )
        let pdfButton = try XCTUnwrap(descendant(
            of: UIButton.self,
            identifier: "health.analytics.pdf.\(analysis.id.uuidString)",
            in: cell.contentView
        ))

        XCTAssertEqual(pdfButton.accessibilityLabel, L10n.text("health.analytics.pdf.open"))
    }

    func testLocalPDFParserOnlyImportsFavoriteBiomarkersAndLaboratoryRanges() throws {
        let (store, _) = try makeStore()
        let glucose = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.glucose_blood" }
        )
        let extraction = ExtractedLabDocument(
            text: """
            Laboratorio: Centro médico
            Fecha: 17/07/2026
            Glucosa 92 mg/dL 70 - 100
            Creatinina 0,91 mg/dL 0,60 - 1,20
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [LabImportBiomarkerDescriptor(biomarker: glucose)],
            fileName: "analitica.pdf"
        )

        XCTAssertEqual(draft.results.count, 1)
        XCTAssertEqual(draft.results.first?.biomarkerID, glucose.id)
        XCTAssertEqual(draft.results.first?.value, 92)
        XCTAssertEqual(draft.results.first?.unit, "mg/dL")
        XCTAssertEqual(draft.results.first?.referenceLower, 70)
        XCTAssertEqual(draft.results.first?.referenceUpper, 100)
        XCTAssertEqual(draft.laboratory, "Centro médico")
        XCTAssertFalse(draft.usedFoundationModels)
    }

    func testLocalPDFParserImportsBareCholesterolValueBeforeUpperLimit() throws {
        let (store, _) = try makeStore()
        let cholesterol = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.cholesterol" }
        )
        let extraction = ExtractedLabDocument(
            text: """
            NOMBRE VALOR UNIDADES RANGO
            COLESTEROL 169,00 mg/dL <200
            COLESTEROL HDL 36,00 mg/dL >40
            COLESTEROL LDL 103,00 mg/dL
            COLESTEROL VLDL 30,00 mg/dL <40
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [LabImportBiomarkerDescriptor(biomarker: cholesterol)],
            fileName: "2024-05-02 Reconocimiento Xunta.pdf"
        )

        let result = try XCTUnwrap(draft.results.first)
        XCTAssertEqual(result.value, 169)
        XCTAssertEqual(result.unit, "mg/dL")
        XCTAssertNil(result.referenceLower)
        XCTAssertEqual(result.referenceUpper, 200)
    }

    func testLocalPDFParserPrefersSpecificGlycatedHemoglobinAlias() throws {
        let (store, _) = try makeStore()
        let hemoglobin = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.hemoglobin" }
        )
        let glycated = try XCTUnwrap(
            store.biomarkers().first {
                $0.nameKey == "health.biomarker.catalog.glycated_hemoglobin"
            }
        )
        let extraction = ExtractedLabDocument(
            text: "Hemoglobina glicosilada 5,4 % 4,0 - 5,6",
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [
                LabImportBiomarkerDescriptor(biomarker: hemoglobin),
                LabImportBiomarkerDescriptor(biomarker: glycated)
            ],
            fileName: "analitica.pdf"
        )

        XCTAssertEqual(draft.results.map(\.biomarkerID), [glycated.id])
        XCTAssertEqual(draft.results.first?.value, Decimal(string: "5.4"))
    }

    func testLocalPDFParserImportsSplit25HydroxyVitaminDResult() throws {
        let (store, _) = try makeStore()
        let vitaminD = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.vitamin_d" }
        )
        let extraction = ExtractedLabDocument(
            text: """
            Metabolismo Oseo
            25-HIDROXI VITAMINA D (Técnica
            CMIA)
            * 15.5 ng/mL < 10 Déficit
            10 - 29 Déficit moderado
            30 - 96 Valores recomendados
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [LabImportBiomarkerDescriptor(biomarker: vitaminD)],
            fileName: "eurofins.pdf"
        )

        let result = try XCTUnwrap(draft.results.first)
        XCTAssertEqual(result.biomarkerID, vitaminD.id)
        XCTAssertEqual(result.value, Decimal(string: "15.5"))
        XCTAssertEqual(result.unit, "ng/mL")
    }

    func testLocalPDFParserImportsSplitGlycatedHemoglobinResult() throws {
        let (store, _) = try makeStore()
        let glycated = try XCTUnwrap(
            store.biomarkers().first {
                $0.nameKey == "health.biomarker.catalog.glycated_hemoglobin"
            }
        )
        let extraction = ExtractedLabDocument(
            text: """
            Hemoglobina glicosilada (HbA1c)
            Unidades NGSP (DCCT) :
            5.4 % < 5.6
            5.7 - 6.4 Riesgo cardiovascular
            > 6.5 Diabetes Mellitus
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [LabImportBiomarkerDescriptor(biomarker: glycated)],
            fileName: "eurofins.pdf"
        )

        let result = try XCTUnwrap(draft.results.first)
        XCTAssertEqual(result.biomarkerID, glycated.id)
        XCTAssertEqual(result.value, Decimal(string: "5.4"))
        XCTAssertEqual(result.unit, "%")
    }

    func testLocalPDFParserMatchesGPTAsAWholeAliasAfterUnrelatedALTSubstrings() throws {
        let (store, _) = try makeStore()
        let alt = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.alt" }
        )
        let extraction = ExtractedLabDocument(
            text: """
            VITALY HEALTH SERVICES, S.L
            Edición 1
            Reconocimiento tras alta laboral
            Bioquímica
            GOT 19 U/L a 37 ºC 0.00 - 50.00
            GPT 19 U/L a 37 ºC 0.00 - 50.00
            GGT 12 U/L a 37 ºC 12.00 - 64.00
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [LabImportBiomarkerDescriptor(biomarker: alt)],
            fileName: "reconocimiento-medico.pdf"
        )

        let result = try XCTUnwrap(draft.results.first)
        XCTAssertEqual(result.value, 19)
        XCTAssertEqual(result.unit, "U/L")
        XCTAssertEqual(result.referenceLower, 0)
        XCTAssertEqual(result.referenceUpper, 50)
    }

    func testLocalPDFParserImportsBarePHFromUrinalysisTable() throws {
        let (store, _) = try makeStore()
        let urinePH = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.ph_urine" }
        )
        let extraction = ExtractedLabDocument(
            text: """
            Análisis de Orina
            DENSIDAD 1.019 1.00 - 1.04
            PH 6 4.50 - 7.50
            PROTEINAS Negativo mg/dL
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [LabImportBiomarkerDescriptor(biomarker: urinePH)],
            fileName: "reconocimiento-medico.pdf"
        )

        let result = try XCTUnwrap(draft.results.first)
        XCTAssertEqual(result.value, 6)
        XCTAssertEqual(result.unit, "pH")
        XCTAssertEqual(result.referenceLower, Decimal(string: "4.50"))
        XCTAssertEqual(result.referenceUpper, Decimal(string: "7.50"))
    }

    func testLocalPDFParserReconstructsAResultSplitAcrossTableCells() throws {
        let (store, _) = try makeStore()
        let glucose = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.glucose_blood" }
        )
        let extraction = ExtractedLabDocument(
            text: """
            Glucosa
            92
            mg/dL
            70 - 100
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [LabImportBiomarkerDescriptor(biomarker: glucose)],
            fileName: "analitica.pdf"
        )

        XCTAssertEqual(draft.results.first?.value, 92)
        XCTAssertEqual(draft.results.first?.referenceLower, 70)
        XCTAssertEqual(draft.results.first?.referenceUpper, 100)
    }

    func testLocalPDFParserLeavesConditionalTriglycerideLimitsForReview() throws {
        let (store, _) = try makeStore()
        let triglycerides = try XCTUnwrap(
            store.biomarkers().first {
                $0.nameKey == "health.biomarker.catalog.triglycerides"
            }
        )
        let extraction = ExtractedLabDocument(
            text: """
            Triglicéridos 105 mg/dl < 150 Tras ayuno de 8-10 horas
                                  < 175 Sin ayuno de 8-10 horas
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [LabImportBiomarkerDescriptor(biomarker: triglycerides)],
            fileName: "2026-07-10 Eurofins.pdf"
        )

        let result = try XCTUnwrap(draft.results.first)
        XCTAssertEqual(result.value, 105)
        XCTAssertNil(result.referenceLower)
        XCTAssertNil(result.referenceUpper)
        XCTAssertTrue(result.notes?.localizedCaseInsensitiveContains("ayuno") == true)
        XCTAssertTrue(result.notes?.contains("< 150") == true)
        XCTAssertTrue(result.notes?.contains("< 175") == true)
    }

    func testLocalPDFParserMapsComparatorsToTheCorrectReferenceBound() throws {
        let (store, _) = try makeStore()
        let triglycerides = try XCTUnwrap(
            store.biomarkers().first {
                $0.nameKey == "health.biomarker.catalog.triglycerides"
            }
        )
        let hdl = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.hdl" }
        )
        let extraction = ExtractedLabDocument(
            text: """
            Triglicéridos 105 mg/dL < 150
            HDL-Colesterol 45 mg/dL > 40
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [
                LabImportBiomarkerDescriptor(biomarker: triglycerides),
                LabImportBiomarkerDescriptor(biomarker: hdl)
            ],
            fileName: "analitica.pdf"
        )

        let resultByBiomarker = Dictionary(
            uniqueKeysWithValues: draft.results.map { ($0.biomarkerID, $0) }
        )
        XCTAssertNil(resultByBiomarker[triglycerides.id]?.referenceLower)
        XCTAssertEqual(resultByBiomarker[triglycerides.id]?.referenceUpper, 150)
        XCTAssertEqual(resultByBiomarker[hdl.id]?.referenceLower, 40)
        XCTAssertNil(resultByBiomarker[hdl.id]?.referenceUpper)
    }

    func testLocalPDFParserDoesNotImportAtherogenicRatioAsHDLCholesterol() throws {
        let (store, _) = try makeStore()
        let cholesterol = try XCTUnwrap(
            store.biomarkers().first {
                $0.nameKey == "health.biomarker.catalog.cholesterol"
            }
        )
        let hdl = try XCTUnwrap(
            store.biomarkers().first {
                $0.nameKey == "health.biomarker.catalog.hdl"
            }
        )
        let extraction = ExtractedLabDocument(
            text: """
            Colesterol 174 mg/dl < 200
            HDL-Colesterol 45 mg/dl > 40
            LDL-Colesterol 108 mg/dL < 116
            Indices de Aterogenicidad
            Cociente (COL.T/HDL-COL) 3.87 < 4.5
            Cociente (LDL-COL/HDL-COL) 2.40 H: < 3.55
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [
                LabImportBiomarkerDescriptor(biomarker: cholesterol),
                LabImportBiomarkerDescriptor(biomarker: hdl)
            ],
            fileName: "2026-07-10 Eurofins.pdf"
        )

        let resultByBiomarker = Dictionary(
            uniqueKeysWithValues: draft.results.map { ($0.biomarkerID, $0) }
        )
        XCTAssertEqual(resultByBiomarker[cholesterol.id]?.value, 174)
        XCTAssertNil(resultByBiomarker[cholesterol.id]?.referenceLower)
        XCTAssertEqual(resultByBiomarker[cholesterol.id]?.referenceUpper, 200)
        XCTAssertEqual(resultByBiomarker[hdl.id]?.value, 45)
        XCTAssertEqual(resultByBiomarker[hdl.id]?.referenceLower, 40)
        XCTAssertNil(resultByBiomarker[hdl.id]?.referenceUpper)
    }

    func testLocalPDFParserDoesNotTreatAUnitExponentAsALeukocyteLimit() throws {
        let (store, _) = try makeStore()
        let leukocytes = try XCTUnwrap(
            store.biomarkers().first {
                $0.nameKey == "health.biomarker.catalog.leukocytes_blood"
            }
        )
        let extraction = ExtractedLabDocument(
            text: "Leucocitos: 4.97 103 /µl 4.00 - 11.00",
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [LabImportBiomarkerDescriptor(biomarker: leukocytes)],
            fileName: "2026-07-10 Eurofins.pdf"
        )

        let result = try XCTUnwrap(draft.results.first)
        XCTAssertEqual(result.value, Decimal(string: "4.97"))
        XCTAssertEqual(result.unit, "10³/µL")
        XCTAssertEqual(result.referenceLower, 4)
        XCTAssertEqual(result.referenceUpper, 11)
    }

    func testLocalPDFParserKeepsPSARangeSeparateFromFreePSAValue() throws {
        let (store, _) = try makeStore()
        let psa = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.psa" }
        )
        let extraction = ExtractedLabDocument(
            text: """
            PSA-Antígeno Prostático Específico
            (Técnica ICMA)
            PSA-Fracción Libre (Técnica
            ICMA)
            1.39 ng/ml < 4
            0.76 ng/mL
            Ratio PSA-Libre/PSA-total 0.55
            Observaciones: Valores de referencia indicativos
            Para valores de PSA-total < 20 ng/ml se ha descrito como
            punto de corte discriminante un valor de ratio de 0.14.
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [LabImportBiomarkerDescriptor(biomarker: psa)],
            fileName: "2026-07-10 Eurofins.pdf"
        )

        let result = try XCTUnwrap(draft.results.first)
        XCTAssertEqual(result.value, Decimal(string: "1.39"))
        XCTAssertNil(result.referenceLower)
        XCTAssertEqual(result.referenceUpper, 4)
    }

    func testLocalPDFParserDoesNotImportFreePSAAsTotalPSA() throws {
        let (store, _) = try makeStore()
        let psa = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.psa" }
        )
        let extraction = ExtractedLabDocument(
            text: """
            PSA-Fracción Libre (Técnica ICMA) 0.76 ng/mL
            Ratio PSA-Libre/PSA-total 0.55
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [LabImportBiomarkerDescriptor(biomarker: psa)],
            fileName: "analitica.pdf"
        )

        XCTAssertTrue(draft.results.isEmpty)
    }

    func testLocalPDFParserDoesNotImportExplanatoryPSAThresholdAsAResult() throws {
        let (store, _) = try makeStore()
        let psa = try XCTUnwrap(
            store.biomarkers().first { $0.nameKey == "health.biomarker.catalog.psa" }
        )
        let extraction = ExtractedLabDocument(
            text: """
            Observaciones: Valores de referencia indicativos
            Para valores de PSA-total < 20 ng/ml se ha descrito como
            punto de corte discriminante un valor de ratio de 0.14.
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [LabImportBiomarkerDescriptor(biomarker: psa)],
            fileName: "analitica.pdf"
        )

        XCTAssertTrue(draft.results.isEmpty)
    }

    func testLocalPDFParserUsesMostRecentDateInsteadOfBirthDate() throws {
        let (store, _) = try makeStore()
        let glucose = try XCTUnwrap(
            store.biomarkers().first {
                $0.nameKey == "health.biomarker.catalog.glucose_blood"
            }
        )
        let extraction = ExtractedLabDocument(
            text: """
            Fecha de nacimiento: 17/05/1984
            Fecha de análisis: 10/07/2026
            Glucosa 92 mg/dL 70 - 100
            """,
            tableText: "",
            usedEmbeddedText: true,
            usedOCR: false,
            usedStructuredRecognition: false
        )

        let draft = LabDocumentResultParser.parse(
            extraction: extraction,
            favorites: [LabImportBiomarkerDescriptor(biomarker: glucose)],
            fileName: "analitica.pdf"
        )

        let components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day],
            from: draft.collectedAt
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 10)
    }

    func testPDFTextExtractorUsesEmbeddedTextWhenAvailable() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WellnarioEmbeddedLab-\(UUID().uuidString).pdf")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 612, height: 792)
        )
        let data = renderer.pdfData { context in
            context.beginPage()
            NSString(string: "Glucosa 92 mg/dL 70 - 100").draw(
                at: CGPoint(x: 40, y: 40),
                withAttributes: [.font: UIFont.systemFont(ofSize: 16)]
            )
        }
        try data.write(to: url)

        let extraction = try await LabPDFTextExtractor.extract(
            from: url,
            customWords: ["Glucosa"]
        )

        XCTAssertTrue(extraction.usedEmbeddedText)
        XCTAssertFalse(extraction.usedOCR)
        XCTAssertTrue(extraction.text.contains("Glucosa 92"))
    }

    func testPDFTextExtractorFallsBackToOCRForImageOnlyPage() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WellnarioScannedLab-\(UUID().uuidString).pdf")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let image = UIGraphicsImageRenderer(bounds: pageBounds).image { context in
            UIColor.white.setFill()
            context.fill(pageBounds)
            NSString(string: "Glucosa 92 mg/dL 70 - 100").draw(
                at: CGPoint(x: 40, y: 80),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 24, weight: .medium),
                    .foregroundColor: UIColor.black
                ]
            )
        }
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            image.draw(in: pageBounds)
        }
        try data.write(to: url)

        let extraction = try await LabPDFTextExtractor.extract(
            from: url,
            customWords: ["Glucosa"]
        )

        XCTAssertFalse(extraction.usedEmbeddedText)
        XCTAssertTrue(extraction.usedOCR)
        XCTAssertTrue(extraction.text.localizedCaseInsensitiveContains("Glucosa"))
        XCTAssertTrue(extraction.text.contains("92"))
    }

    private func makeStore() throws -> (HealthDataStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WellnarioHealthTests-\(UUID().uuidString).sqlite")
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        return (try HealthDataStore(databaseURL: url), url)
    }

    private func makeAnalysis(
        biomarkerID: UUID,
        value: Decimal,
        date: Date
    ) -> LabAnalysis {
        LabAnalysis(
            id: UUID(),
            collectedAt: date,
            laboratory: nil,
            notes: nil,
            results: [
                LabResult(
                    id: UUID(),
                    biomarkerID: biomarkerID,
                    value: value,
                    unit: "mg/dL",
                    referenceLower: 70,
                    referenceUpper: 100
                )
            ]
        )
    }

    private func descendant<View: UIView>(
        of type: View.Type,
        identifier: String,
        in root: UIView
    ) -> View? {
        if let view = root as? View, view.accessibilityIdentifier == identifier {
            return view
        }
        for subview in root.subviews {
            if let match = descendant(of: type, identifier: identifier, in: subview) {
                return match
            }
        }
        return nil
    }
}
