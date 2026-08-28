import SwiftUI

#if os(iOS) && canImport(VisionKit)
import AVFoundation
import Vision
import VisionKit

/// Controls how the scanner should treat recognized camera text.
///
/// Name capture is manual because the user should choose the best medicine name.
/// It shows only short same-row candidates and ignores sentence-like OCR results.
/// Tapping a word in the camera appends that single word to the captured name.
/// Single-date capture shows only date-like values and requires the user to tap one.
enum TextScannerCaptureMode {
    case manualText
    case singleDate

    /// Text shown on the bottom-middle confirmation button.
    var confirmButtonTitle: String {
        switch self {
        case .manualText:
            return "OK"
        case .singleDate:
            return "Capture"
        }
    }
}

/// User-friendly scanner screen shown inside the sheet.
///
/// The camera is displayed inside a rectangular area so users can aim at only the useful
/// label text. For medicine names, the user selects the right text. For dates, the scanner
/// automatically filters OCR output down to date-like values only.
struct TextScannerView: View {
    let title: String
    let instructions: String
    let captureMode: TextScannerCaptureMode
    let onConfirm: ([String]) -> Void
    let onClose: () -> Void

    @State private var detectedTexts: [String] = []
    @State private var capturedTexts: [String] = []
    @State private var selectedDateText: String?
    @State private var selectedDateIsValid = false
    @State private var isTorchOn = false

    /// First name candidate seen in the session. Live OCR sends larger text first, so
    /// this is the best guess for the medicine name.
    private var suggestedName: String? {
        detectedTexts.first
    }

    /// The values that will be sent back to `ContentView` when the user taps the bottom button.
    private var confirmableTexts: [String] {
        switch captureMode {
        case .manualText:
            return capturedTexts
        case .singleDate:
            return selectedDateText.map { [$0] } ?? []
        }
    }

    /// Word-at-tap capture is a name-mode feature; date mode keeps whole-line taps.
    private var wordTapHandler: ((String) -> Void)? {
        guard captureMode == .manualText else { return nil }
        return appendTappedWord
    }

    /// Whether the bottom confirmation button should be enabled.
    private var canConfirm: Bool {
        switch captureMode {
        case .manualText: return !capturedTexts.isEmpty
        case .singleDate: return selectedDateIsValid
        }
    }

    /// Builds the scanner screen with camera, detected values, and bottom actions.
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(ScannerPalette.ink)
                Text(instructions)
                    .font(.subheadline)
                    .foregroundStyle(ScannerPalette.ink.opacity(0.68))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScannerCameraView(
                isTorchOn: isTorchOn,
                onTextTapped: handleTappedText,
                onWordTapped: wordTapHandler,
                onDetectedTextsChanged: updateDetectedTexts
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white, lineWidth: 3)
                    .shadow(radius: 4)
            }
            .overlay(alignment: .bottom) {
                Text("Keep label text inside this box")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 10)
            }
            .overlay(alignment: .topTrailing) {
                // Extra light helps OCR read low-contrast print, such as red medicine names.
                Button {
                    isTorchOn.toggle()
                } label: {
                    Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isTorchOn ? .yellow : .white)
                        .padding(10)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel(isTorchOn ? "Turn torch off" : "Turn torch on")
            }

            textSelectionArea

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Button("Cancel", action: onClose)
                    .buttonStyle(DimensionalButtonStyle(fill: ScannerPalette.blue, prominence: .secondary, minHeight: 42))

                Button {
                    onConfirm(confirmableTexts)
                } label: {
                    Text(captureMode.confirmButtonTitle)
                        .frame(minWidth: 140)
                }
                .buttonStyle(DimensionalButtonStyle(fill: ScannerPalette.coral, minHeight: 42))
                .disabled(!canConfirm)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
        }
        .padding()
        .fontDesign(.rounded)
        .environment(\.colorScheme, .light)
        .background(ScannerPalette.background)
        .preferredColorScheme(.light)
        .onChange(of: selectedDateText) { _, newValue in
            selectedDateIsValid = newValue.map { MedicineDateParser.firstDate(from: $0) != nil } ?? false
        }
    }

    /// Shows either manual text selection or automatic date detection, depending on mode.
    @ViewBuilder
    private var textSelectionArea: some View {
        switch captureMode {
        case .manualText:
            manualTextSelectionArea
        case .singleDate:
            singleDateCaptureArea
        }
    }

    /// UI for selecting a medicine name from detected OCR text.
    private var manualTextSelectionArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !detectedTexts.isEmpty {
                Text("Suggested name")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ScannerPalette.ink)

                VStack(alignment: .leading, spacing: 8) {
                    if let suggestedName {
                        Button {
                            addCapturedText(suggestedName)
                        } label: {
                            Label(suggestedName, systemImage: "text.magnifyingglass")
                                .font(.headline.weight(.bold))
                        }
                        .buttonStyle(DimensionalButtonStyle(fill: ScannerPalette.teal, minHeight: 42))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(detectedTexts, id: \.self) { text in
                                Button {
                                    addCapturedText(text)
                                } label: {
                                    Text(text)
                                        .lineLimit(1)
                                }
                                .buttonStyle(DimensionalButtonStyle(fill: ScannerPalette.blue, prominence: .secondary, minHeight: 36))
                            }
                        }
                    }
                }
            }

            Text("Captured values")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ScannerPalette.ink)

            if capturedTexts.isEmpty {
                Text("Point at the biggest/boldest medicine name, then tap the suggestion, or tap each word of the name in the camera view.")
                    .font(.footnote)
                    .foregroundStyle(ScannerPalette.ink.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                capturedTextList
            }
        }
    }

    /// UI for selecting one date from detected OCR date values.
    private var singleDateCaptureArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detected dates")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ScannerPalette.ink)

            if detectedTexts.isEmpty {
                Text("No dates detected yet. Hold the date inside the box.")
                    .font(.footnote)
                    .foregroundStyle(ScannerPalette.ink.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(detectedTexts, id: \.self) { text in
                            Button {
                                selectedDateText = text
                            } label: {
                                HStack(spacing: 6) {
                                    if selectedDateText == text {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                    Text(text)
                                        .font(.body.monospacedDigit())
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(DimensionalButtonStyle(
                                fill: selectedDateText == text ? ScannerPalette.teal : ScannerPalette.blue,
                                prominence: selectedDateText == text ? .primary : .secondary,
                                minHeight: 38
                            ))
                        }
                    }
                }

                if selectedDateText == nil {
                    Label("Tap the correct date, then press Capture.", systemImage: "hand.tap.fill")
                        .font(.footnote)
                        .foregroundStyle(ScannerPalette.ink.opacity(0.6))
                } else if canConfirm {
                    Label("Selected date is valid.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(ScannerPalette.teal)
                }
            }
        }
    }

    /// List of manually captured text values with remove buttons.
    private var capturedTextList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(capturedTexts, id: \.self) { text in
                    HStack {
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)

                        Button {
                            removeCapturedText(text)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .imageScale(.large)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ScannerPalette.ink.opacity(0.6))
                        .accessibilityLabel("Remove \(text)")
                    }
                    .padding(10)
                    .background(ScannerPalette.mint.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .frame(maxHeight: 140)
    }

    /// Updates detected values from the camera.
    ///
    /// Name mode filters raw OCR down to short medicine-name candidates, so sentences from the
    /// medicine label are ignored.
    /// Date mode filters the raw OCR strings down to date-like values only before showing
    /// them, so unrelated medicine text cannot be captured into the date fields.
    /// In both modes, detected values accumulate for the whole scanning session instead
    /// of vanishing when the camera moves away or loses focus.
    private func updateDetectedTexts(_ texts: [String]) {
        switch captureMode {
        case .manualText:
            mergeDetectedNames(MedicineNameParser.candidates(from: texts))
        case .singleDate:
            mergeDetectedDates(dateValues(from: texts))
        }
    }

    /// Adds newly detected name candidates to the on-screen list, skipping duplicates.
    ///
    /// Comparison is case-insensitive, so OCR re-reading "DOLO 650" as "Dolo 650" does
    /// not create a second entry; the first-seen casing is kept.
    private func mergeDetectedNames(_ names: [String]) {
        for name in names {
            let isDuplicate = detectedTexts.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            if !isDuplicate {
                detectedTexts.append(name)
            }
        }
    }

    /// Handles a whole recognized line tapped inside VisionKit's camera highlight layer.
    ///
    /// Name mode suppresses this callback and captures the single tapped word through
    /// `appendTappedWord` instead. In date mode this updates detected dates automatically
    /// instead of manually adding arbitrary text to the captured list.
    private func handleTappedText(_ text: String) {
        switch captureMode {
        case .manualText:
            if let candidate = MedicineNameParser.candidate(from: text) {
                addCapturedText(candidate)
            }
        case .singleDate:
            let dates = dateValues(from: [text])
            guard let firstDate = dates.first else { return }
            mergeDetectedDates(dates)
            selectedDateText = existingDetectedDate(matching: firstDate) ?? firstDate
        }
    }

    /// Adds newly detected dates to the on-screen list, skipping duplicates.
    ///
    /// Two values count as duplicates when they parse to the same calendar date, even if
    /// the label prints them in different formats (for example "08/2027" and "AUG 2027").
    private func mergeDetectedDates(_ dates: [String]) {
        for date in dates where existingDetectedDate(matching: date) == nil {
            detectedTexts.append(date)
        }
    }

    /// Returns the already-listed value equivalent to the given date string, if any.
    private func existingDetectedDate(matching date: String) -> String? {
        if detectedTexts.contains(date) {
            return date
        }
        guard let parsed = MedicineDateParser.firstDate(from: date) else { return nil }
        return detectedTexts.first { MedicineDateParser.firstDate(from: $0) == parsed }
    }

    /// Appends one word tapped in the camera view to the working captured name.
    ///
    /// Tapping "Crocin" and then "Advance" builds the single value "Crocin Advance".
    /// Repeating the same word twice in a row is treated as an accidental double tap.
    private func appendTappedWord(_ word: String) {
        let cleaned = cleanedText(word)
        guard !cleaned.isEmpty else { return }

        guard let workingName = capturedTexts.last else {
            capturedTexts.append(cleaned)
            return
        }

        let lastWord = workingName.split(separator: " ").last.map(String.init)
        guard lastWord?.caseInsensitiveCompare(cleaned) != .orderedSame else { return }
        capturedTexts[capturedTexts.count - 1] = workingName + " " + cleaned
    }

    /// Adds a recognized text value if it is not blank or already selected.
    private func addCapturedText(_ text: String) {
        let cleaned = cleanedText(text)
        guard !cleaned.isEmpty, !capturedTexts.contains(cleaned) else { return }
        capturedTexts.append(cleaned)
    }

    /// Removes one selected value from the captured list.
    private func removeCapturedText(_ text: String) {
        capturedTexts.removeAll { $0 == text }
    }

    /// Extracts unique date strings from OCR text.
    private func dateValues(from texts: [String]) -> [String] {
        var seen: Set<String> = []
        var dates: [String] = []

        for text in texts {
            for date in MedicineDateParser.extractDateStrings(from: text) {
                guard !seen.contains(date) else { continue }
                seen.insert(date)
                dates.append(date)
            }
        }

        return dates
    }

    /// Normalizes camera text before showing it to the user.
    private func cleanedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// SwiftUI wrapper around `DataScannerViewController`.
private struct ScannerCameraView: UIViewControllerRepresentable {
    let isTorchOn: Bool
    let onTextTapped: (String) -> Void
    let onWordTapped: ((String) -> Void)?
    let onDetectedTextsChanged: ([String]) -> Void

    /// Creates the UIKit controller that SwiftUI embeds inside the rectangular camera area.
    func makeUIViewController(context: Context) -> UIViewController {
        ScannerHostViewController(
            delegate: context.coordinator,
            onWordTapped: onWordTapped,
            onDetectedTextsChanged: onDetectedTextsChanged
        )
    }

    /// Pushes SwiftUI state changes, such as the torch toggle, down to the camera controller.
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? ScannerHostViewController)?.setTorch(enabled: isTorchOn)
    }

    /// When word taps are enabled, whole-line taps are suppressed so a single tap does
    /// not capture both the tapped word and the full recognized line.
    func makeCoordinator() -> Coordinator {
        Coordinator(onTextTapped: onWordTapped == nil ? onTextTapped : nil)
    }

    /// Receives VisionKit scanner events and forwards useful text back to SwiftUI.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onTextTapped: ((String) -> Void)?

        /// Stores the callback that should run when the user taps recognized text.
        init(onTextTapped: ((String) -> Void)?) {
            self.onTextTapped = onTextTapped
        }

        /// Runs when the user taps a recognized item in the camera view.
        ///
        /// VisionKit can recognize different item types. This app only uses `.text`.
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard let onTextTapped else { return }
            if case let .text(text) = item {
                onTextTapped(text.transcript)
            }
        }
    }
}

/// Owns the actual camera scanner and camera-permission flow.
///
/// Keeping this in a UIKit controller makes it easier to embed VisionKit cleanly and
/// show clear fallback messages when permission or device support is missing.
private final class ScannerHostViewController: UIViewController {
    private weak var scannerDelegate: DataScannerViewControllerDelegate?
    private let onWordTapped: ((String) -> Void)?
    private let onDetectedTextsChanged: ([String]) -> Void
    private var scanner: DataScannerViewController?
    private var recognizedItemsTask: Task<Void, Never>?
    private var lastDetectedTexts: [String] = []
    private var lastDetectedUpdate = Date.distantPast
    private var isTorchEnabled = false

    /// Latest items from the camera, kept so a tap can be matched to on-screen text.
    private var latestRecognizedItems: [RecognizedItem] = []

    /// Creates the scanner host with a delegate and live detected-text callback.
    init(
        delegate: DataScannerViewControllerDelegate,
        onWordTapped: ((String) -> Void)?,
        onDetectedTextsChanged: @escaping ([String]) -> Void
    ) {
        self.scannerDelegate = delegate
        self.onWordTapped = onWordTapped
        self.onDetectedTextsChanged = onDetectedTextsChanged
        super.init(nibName: nil, bundle: nil)
    }

    /// Not used — this controller is created in code, never from a storyboard.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        recognizedItemsTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        showStatus("Preparing camera...")
        configureCameraAccess()
    }

    /// Stops scanning when the embedded camera view is removed.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isTorchEnabled = false
        applyTorchState()
        scanner?.stopScanning()
        recognizedItemsTask?.cancel()
    }

    /// Turns the camera torch on or off to help read low-contrast label print.
    ///
    /// The torch belongs to the same back camera VisionKit scans with, so lighting it
    /// while the session runs brightens exactly what the scanner sees.
    func setTorch(enabled: Bool) {
        guard isTorchEnabled != enabled else { return }
        isTorchEnabled = enabled
        applyTorchState()
    }

    /// Applies the requested torch state to the camera hardware, when available.
    ///
    /// Devices without a torch (and the simulator) are skipped silently; torch failures
    /// are non-fatal and scanning simply continues without the extra light.
    private func applyTorchState() {
        guard scanner != nil,
              let device = AVCaptureDevice.default(for: .video),
              device.hasTorch, device.isTorchAvailable else { return }

        do {
            try device.lockForConfiguration()
            device.torchMode = isTorchEnabled ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Leaving the torch in its previous state is acceptable.
        }
    }

    /// Checks the app's camera setup and requests permission if needed.
    ///
    /// The app must have `NSCameraUsageDescription` in its Info settings or iOS will not
    /// allow camera access. After permission is granted, this method starts the scanner.
    private func configureCameraAccess() {
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else {
            showUnavailable(
                "Camera permission text is missing. Add Privacy - Camera Usage Description to the app target Info settings, then reinstall the app."
            )
            return
        }

        guard DataScannerViewController.isSupported else {
            showUnavailable("Live text scanning is not supported on this device.")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startScanner()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    if granted {
                        self?.startScanner()
                    } else {
                        self?.showUnavailable("Camera access was denied. Enable it in Settings to scan medicine labels.")
                    }
                }
            }
        case .denied, .restricted:
            showUnavailable("Camera access is disabled. Enable it in Settings to scan medicine labels.")
        @unknown default:
            showUnavailable("Camera access is unavailable on this device.")
        }
    }

    /// Creates and starts VisionKit's live text scanner.
    ///
    /// The scanner fills this controller's rectangular view and highlights text the camera can read.
    private func startScanner() {
        guard DataScannerViewController.isAvailable else {
            showUnavailable("Text scanning is currently unavailable. Check Camera permission and device restrictions.")
            return
        }

        // .accurate uses the stronger recognition model, which reads colored and
        // stylized label print (such as red medicine names) more reliably than .balanced.
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = scannerDelegate
        self.scanner = scanner

        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.subviews.forEach { $0.removeFromSuperview() }
        view.addSubview(scanner.view)
        NSLayoutConstraint.activate([
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        scanner.didMove(toParent: self)

        if onWordTapped != nil {
            // Runs alongside VisionKit's own gestures; it only reads the tap location.
            let wordTap = UITapGestureRecognizer(target: self, action: #selector(handleWordTap(_:)))
            wordTap.cancelsTouchesInView = false
            wordTap.delegate = self
            scanner.view.addGestureRecognizer(wordTap)
        }

        do {
            try scanner.startScanning()
            observeRecognizedItems(from: scanner)
            // Honor a torch toggle made while the camera was still starting up.
            applyTorchState()
        } catch {
            showUnavailable("Could not start camera scanning. Try closing and reopening the scanner.")
        }
    }

    /// Captures the single word under the user's finger.
    ///
    /// VisionKit's own tap callback only reports the whole recognized line, so this
    /// gesture finds the tapped line itself, works out how far along the line the tap
    /// landed, and picks the space-delimited word at that position.
    @objc private func handleWordTap(_ gesture: UITapGestureRecognizer) {
        guard let scanner, let onWordTapped else { return }

        let point = gesture.location(in: scanner.view)
        guard let (text, fraction) = Self.tappedTextItem(at: point, in: latestRecognizedItems) else { return }

        if let word = Self.word(atFraction: fraction, in: text) {
            onWordTapped(word)
        }
    }

    /// Finds the recognized text line under the tap, with a small touch padding.
    ///
    /// Returns the line plus the tap's fraction along it (0 = left edge, 1 = right edge).
    /// When highlighted lines overlap, the one whose centre is closest to the tap wins.
    private static func tappedTextItem(
        at point: CGPoint,
        in items: [RecognizedItem]
    ) -> (text: RecognizedItem.Text, fraction: CGFloat)? {
        var best: (text: RecognizedItem.Text, fraction: CGFloat, distance: CGFloat)?

        for item in items {
            guard case let .text(text) = item else { continue }

            let bounds = text.bounds
            let corners = [bounds.topLeft, bounds.topRight, bounds.bottomRight, bounds.bottomLeft]
            guard contains(point: point, inQuad: corners, padding: 12) else { continue }

            let center = CGPoint(
                x: corners.map(\.x).reduce(0, +) / 4,
                y: corners.map(\.y).reduce(0, +) / 4
            )
            let distance = hypot(point.x - center.x, point.y - center.y)
            if best.map({ distance < $0.distance }) ?? true {
                best = (text, fractionAlongLine(of: point, in: bounds), distance)
            }
        }

        return best.map { ($0.text, $0.fraction) }
    }

    /// Tests whether a point lies inside the four recognized-text corners.
    ///
    /// The corners are pushed outward from their centre by `padding` first, because a
    /// fingertip tap is less precise than the pixel-accurate OCR quadrilateral.
    private static func contains(point: CGPoint, inQuad corners: [CGPoint], padding: CGFloat) -> Bool {
        let center = CGPoint(
            x: corners.map(\.x).reduce(0, +) / 4,
            y: corners.map(\.y).reduce(0, +) / 4
        )
        let expanded = corners.map { corner -> CGPoint in
            let dx = corner.x - center.x
            let dy = corner.y - center.y
            let length = max(hypot(dx, dy), 0.0001)
            let scale = (length + padding) / length
            return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
        }

        // The point is inside a convex quad when it sits on the same side of all edges.
        var previousSign: CGFloat = 0
        for index in 0..<4 {
            let a = expanded[index]
            let b = expanded[(index + 1) % 4]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            if cross == 0 { continue }
            let sign: CGFloat = cross > 0 ? 1 : -1
            if previousSign == 0 {
                previousSign = sign
            } else if sign != previousSign {
                return false
            }
        }
        return true
    }

    /// How far along the recognized line the tap landed, using the line's own axis.
    ///
    /// Projecting onto the line's midline keeps this correct even when the label is
    /// photographed at an angle and the quadrilateral is not axis-aligned.
    private static func fractionAlongLine(of point: CGPoint, in bounds: RecognizedItem.Bounds) -> CGFloat {
        let left = CGPoint(
            x: (bounds.topLeft.x + bounds.bottomLeft.x) / 2,
            y: (bounds.topLeft.y + bounds.bottomLeft.y) / 2
        )
        let right = CGPoint(
            x: (bounds.topRight.x + bounds.bottomRight.x) / 2,
            y: (bounds.topRight.y + bounds.bottomRight.y) / 2
        )
        let dx = right.x - left.x
        let dy = right.y - left.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return 0 }

        let projection = ((point.x - left.x) * dx + (point.y - left.y) * dy) / lengthSquared
        return min(max(projection, 0), 1)
    }

    /// Returns the space-delimited word at the given fraction along a recognized line.
    private static func word(atFraction fraction: CGFloat, in text: RecognizedItem.Text) -> String? {
        // Prefer Vision's per-word geometry; it stays accurate when words have different widths.
        if let candidate = text.observation.topCandidates(1).first,
           let word = word(atFraction: fraction, in: candidate) {
            return word
        }

        // Fallback: assume characters are evenly spaced along the line.
        let transcript = text.transcript
        let tokens = spaceDelimitedTokens(in: transcript)
        guard !tokens.isEmpty else { return nil }

        let offset = min(max(Int(fraction * CGFloat(transcript.count)), 0), transcript.count - 1)
        let tappedIndex = transcript.index(transcript.startIndex, offsetBy: offset)
        return tokens.last { $0.range.lowerBound <= tappedIndex }?.token ?? tokens[0].token
    }

    /// Picks the word whose Vision bounding box covers the tapped fraction of the line.
    private static func word(atFraction fraction: CGFloat, in candidate: VNRecognizedText) -> String? {
        let string = candidate.string
        let tokens = spaceDelimitedTokens(in: string)
        guard tokens.count > 1 else { return tokens.first?.token }

        guard let fullBox = (try? candidate.boundingBox(for: string.startIndex..<string.endIndex))?.boundingBox,
              fullBox.width > 0 else { return nil }

        var nearest: (token: String, distance: CGFloat)?
        for (token, range) in tokens {
            guard let box = (try? candidate.boundingBox(for: range))?.boundingBox else { continue }

            let start = (box.minX - fullBox.minX) / fullBox.width
            let end = (box.maxX - fullBox.minX) / fullBox.width
            if fraction >= start && fraction <= end {
                return token
            }

            let distance = abs(fraction - (start + end) / 2)
            if nearest.map({ distance < $0.distance }) ?? true {
                nearest = (token, distance)
            }
        }
        return nearest?.token
    }

    /// Splits text into words separated by whitespace, keeping each word's range.
    private static func spaceDelimitedTokens(in text: String) -> [(token: String, range: Range<String.Index>)] {
        var tokens: [(token: String, range: Range<String.Index>)] = []
        var index = text.startIndex

        while index < text.endIndex {
            if text[index].isWhitespace {
                index = text.index(after: index)
                continue
            }

            var end = index
            while end < text.endIndex, !text[end].isWhitespace {
                end = text.index(after: end)
            }
            tokens.append((String(text[index..<end]), index..<end))
            index = end
        }

        return tokens
    }

    /// Watches VisionKit's live recognized text stream and sends readable strings to SwiftUI.
    private func observeRecognizedItems(from scanner: DataScannerViewController) {
        recognizedItemsTask?.cancel()
        recognizedItemsTask = Task { @MainActor [weak self, weak scanner] in
            guard let scanner else { return }
            for await items in scanner.recognizedItems {
                self?.latestRecognizedItems = items
                let texts = Self.texts(from: items)
                self?.publishDetectedTextsIfNeeded(texts)
            }
        }
    }

    /// Publishes detected text to SwiftUI only when useful.
    ///
    /// VisionKit updates very frequently while focusing. Updating SwiftUI on every camera
    /// frame makes the text area look like it is constantly refreshing, so this method
    /// ignores duplicate updates, throttles rapid changes, and keeps the previous useful
    /// result when the camera briefly reports no text.
    private func publishDetectedTextsIfNeeded(_ texts: [String]) {
        guard !texts.isEmpty else { return }
        guard texts != lastDetectedTexts else { return }

        let now = Date()
        guard now.timeIntervalSince(lastDetectedUpdate) > 0.6 else { return }

        lastDetectedTexts = texts
        lastDetectedUpdate = now
        onDetectedTextsChanged(texts)
    }

    /// Pulls unique text transcripts out of VisionKit recognized items.
    ///
    /// Larger text is a useful clue for medicine-name labels, so recognized items are
    /// sorted by their on-screen area before their transcripts are sent to SwiftUI.
    private static func texts(from items: [RecognizedItem]) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []

        for item in items.sorted(by: { textArea(for: $0) > textArea(for: $1) }) {
            guard case let .text(text) = item else { continue }
            let transcript = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty, !seen.contains(transcript) else { continue }
            seen.insert(transcript)
            results.append(transcript)
        }

        return results
    }

    /// Approximates how visually large a recognized item is in the camera view.
    ///
    /// VisionKit gives four corners instead of a simple rectangle. Multiplying the top
    /// edge width by the left edge height gives a stable enough area for ranking labels.
    private static func textArea(for item: RecognizedItem) -> CGFloat {
        guard case let .text(text) = item else { return 0 }

        let bounds = text.bounds
        let width = hypot(bounds.topRight.x - bounds.topLeft.x, bounds.topRight.y - bounds.topLeft.y)
        let height = hypot(bounds.bottomLeft.x - bounds.topLeft.x, bounds.bottomLeft.y - bounds.topLeft.y)
        return width * height
    }

    private func showStatus(_ message: String) {
        showMessage(message)
    }

    private func showUnavailable(_ message: String) {
        showMessage(message)
    }

    private func showMessage(_ message: String) {
        view.subviews.forEach { $0.removeFromSuperview() }

        let label = UILabel()
        label.text = message
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .footnote)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
/// Lets the word-tap gesture run without blocking VisionKit's built-in gestures,
/// such as pinch-to-zoom and its own tap highlighting.
extension ScannerHostViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

/// Light scanner-sheet colors that match the main PillEye screen.
private enum ScannerPalette {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.94, green: 0.99, blue: 0.97),
            Color(red: 0.98, green: 0.97, blue: 1.00)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let mint = PillEyePalette.mint
    static let teal = PillEyePalette.teal
    static let coral = PillEyePalette.coral
    static let blue = PillEyePalette.blue
    static let ink = PillEyePalette.ink
}
#else
/// Fallback scanner view for platforms where VisionKit is not available.
struct TextScannerView: View {
    let title: String
    let instructions: String
    let captureMode: TextScannerCaptureMode
    let onConfirm: ([String]) -> Void
    let onClose: () -> Void

    /// Shows a simple unsupported-platform message.
    var body: some View {
        VStack(spacing: 16) {
            Text("Camera text scanning is only available on supported iOS devices.")
                .multilineTextAlignment(.center)
            Button("Close", action: onClose)
                .buttonStyle(DimensionalButtonStyle(fill: .blue, minHeight: 42))
        }
        .padding()
    }
}
#endif
