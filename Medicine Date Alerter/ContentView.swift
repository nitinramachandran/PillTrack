import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The main screen of the app.
struct ContentView: View {
    @AppStorage("hasSeenCameraOnboarding") private var hasSeenOnboarding = false
    @State private var store: MedicineStore
    @State private var medicineName = ""
    @State private var manufacturingDate: Date?
    @State private var expiryDate: Date?
    @State private var reminderLeadDays = 1
    @State private var activeDateField: ManualDateTarget = .manufacturing
    @State private var validationMessage: String?
    @State private var showingScanner = false
    @State private var scannerMode = ScannerMode.name
    @State private var manualDateTarget: ManualDateTarget?
    @State private var manualDateDraft = Date()
    @State private var notificationMedicineID: UUID?
    @State private var medicineEditDraft: MedicineEditDraft?
    @State private var savedConfirmation: Medicine?
    @State private var showingSavedMedicines = false
    @State private var pendingPhotoData: Data?
    @State private var showingPhotoOptions = false
    @State private var showingCameraCapture = false
    @State private var showingPhotoLibrary = false
    @State private var showingCameraUnavailableAlert = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showingBackupImporter = false
    @State private var pendingImportData: Data?
    @State private var backupMessage: String?

    /// The medicine selected by tapping an expiry notification, if it still exists in the store.
    private var notificationMedicine: Medicine? {
        guard let notificationMedicineID else { return nil }
        return store.medicines.first { $0.id == notificationMedicineID }
    }

    /// The current medicines as a shareable backup, or `nil` when there is nothing to export.
    private var backupShareItem: MedicineBackupFile? {
        guard !store.medicines.isEmpty, let data = try? store.exportData() else { return nil }
        return MedicineBackupFile(data: data)
    }

    /// Shows the replace-confirmation alert while a picked backup waits for approval.
    private var isConfirmingImport: Binding<Bool> {
        Binding(
            get: { pendingImportData != nil },
            set: { isPresented in
                if !isPresented {
                    pendingImportData = nil
                }
            }
        )
    }

    /// Creates the real app screen with the disk-backed medicine store.
    @MainActor
    init() {
        _store = State(initialValue: MedicineStore())
    }

    /// Creates the screen with a supplied store.
    ///
    /// This initializer is mainly useful for previews and tests, where we do not want
    /// to use real notification scheduling.
    init(store: MedicineStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    headerPanel
                }
                .listRowBackground(Color.clear)

                Section("Medicine details") {
                    TextField("Medicine name", text: $medicineName)
                        .font(.body.weight(.semibold))
                        .textInputAutocapitalization(.words)
                        .foregroundStyle(PillEyePalette.deepTeal)
                        .accessibilityIdentifier("medicineNameField")

                    HStack {
                        Button {
                            scannerMode = .name
                            showingScanner = true
                        } label: {
                            Label("Scan medicine name", systemImage: "camera.viewfinder")
                        }
                        .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.teal))

                        Button("Clear") {
                            medicineName = ""
                        }
                        .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.coral, prominence: .secondary))
                        .disabled(medicineName.isEmpty)
                        .accessibilityIdentifier("clearMedicineNameButton")
                    }

                    photoAttachmentRow

                    dateEntryRow

                    Picker("Remind before expiry", selection: $reminderLeadDays) {
                        ForEach(ReminderLeadOption.allDays, id: \.self) { days in
                            Text(ReminderLeadOption.label(for: days)).tag(days)
                        }
                    }
                }
                .listRowBackground(PillEyePalette.formRowBackground)

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PillEyePalette.coral)
                            .accessibilityIdentifier("validationMessage")
                    }
                    .listRowBackground(PillEyePalette.formRowBackground)
                }

                Section {
                    Button {
                        Task { await saveMedicine() }
                    } label: {
                        Label("Save medicine", systemImage: "tray.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.coral, minHeight: 46))
                    .accessibilityIdentifier("saveMedicineButton")
                }
                .listRowBackground(PillEyePalette.formRowBackground)

                Section {
                    Button {
                        showingSavedMedicines = true
                    } label: {
                        Label(
                            store.medicines.isEmpty
                                ? "Saved medicines"
                                : "Saved medicines (\(store.medicines.count))",
                            systemImage: "list.bullet.rectangle.portrait.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.teal, minHeight: 46))
                    .accessibilityIdentifier("savedMedicinesButton")
                }
                .listRowBackground(PillEyePalette.formRowBackground)

                Section {
                    if let backup = backupShareItem {
                        ShareLink(
                            item: backup,
                            preview: SharePreview(
                                "MedXpiryTracker medicines backup",
                                image: Image(systemName: "cross.case.fill")
                            )
                        ) {
                            Label("Export data", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.blue))
                        .accessibilityIdentifier("exportMedicinesButton")
                    }

                    Button {
                        backupMessage = nil
                        showingBackupImporter = true
                    } label: {
                        Label("Import data", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.blue, prominence: .secondary))
                    .accessibilityIdentifier("importMedicinesButton")

                    if let backupMessage {
                        Label(backupMessage, systemImage: "info.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PillEyePalette.deepTeal)
                            .accessibilityIdentifier("backupMessage")
                    }
                } header: {
                    Text("Backup & transfer")
                } footer: {
                    Text("Backups are plain files. AirDrop one to another iPhone or keep it in Files, then import it after switching phones or reinstalling.")
                }
                .listRowBackground(PillEyePalette.formRowBackground)
            }
            .fontDesign(.rounded)
            .environment(\.colorScheme, .light)
            .tint(PillEyePalette.teal)
            .scrollContentBackground(.hidden)
            .background(PillEyePalette.background)
            .navigationTitle("Track my Meds")
            .toolbarBackground(PillEyePalette.mint, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .sheet(isPresented: $showingScanner) {
                NavigationStack {
                    TextScannerView(
                        title: scannerMode.title,
                        instructions: scannerMode.instructions,
                        captureMode: scannerMode.captureMode,
                        onConfirm: applyCapturedTexts,
                        onClose: { showingScanner = false }
                    )
                    .fontDesign(.rounded)
                    .tint(PillEyePalette.teal)
                    .navigationTitle(scannerMode.title)
                }
            }
            .sheet(isPresented: $showingSavedMedicines) {
                SavedMedicinesView(
                    store: store,
                    onEdit: { medicine in
                        showingSavedMedicines = false
                        openMedicineEditPopup(for: medicine)
                    },
                    onDelete: { medicine in
                        await deleteMedicine(medicine)
                    },
                    onClose: { showingSavedMedicines = false }
                )
            }
            .overlay {
                if let manualDateTarget {
                    manualDatePopup(for: manualDateTarget)
                } else if let medicineEditDraft {
                    medicineEditPopup(for: medicineEditDraft)
                } else if let notificationMedicine {
                    medicineDetailsPopup(for: notificationMedicine)
                }
            }
            .overlay {
                if let savedConfirmation {
                    saveConfirmationCard(for: savedConfirmation)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .sheet(isPresented: $showingCameraCapture) {
                CameraPhotoPicker(
                    onCapture: { data in
                        pendingPhotoData = data
                    },
                    onClose: { showingCameraCapture = false }
                )
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $showingPhotoLibrary,
                selection: $photoPickerItem,
                matching: .all(of: [.images, .not(.livePhotos)])
            )
            .onChange(of: photoPickerItem) { _, newItem in
                loadPickedPhoto(newItem)
            }
            .fileImporter(
                isPresented: $showingBackupImporter,
                allowedContentTypes: [.json]
            ) { result in
                handleBackupSelection(result)
            }
            .alert("Replace saved medicines?", isPresented: isConfirmingImport) {
                Button("Replace", role: .destructive) {
                    if let pendingImportData {
                        Task { await importBackup(pendingImportData) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Importing replaces your \(store.medicines.count) saved medicine\(store.medicines.count == 1 ? "" : "s") with the contents of the backup file.")
            }
            .task { await store.load() }
            .task { await listenForNotificationTaps() }
        }
        .overlay {
            if !hasSeenOnboarding {
                cameraOnboardingOverlay
            }
        }
        .preferredColorScheme(.light)
    }

    /// Waits for notification-tap events from `AppNotificationDelegate`.
    private func listenForNotificationTaps() async {
        if let pendingMedicineID = MedicineNotificationRoute.consumePendingMedicineID() {
            openNotificationMedicineDetails(for: pendingMedicineID)
        }

        for await notification in NotificationCenter.default.notifications(named: MedicineNotificationRoute.medicineTapped) {
            guard let medicineID = MedicineNotificationRoute.medicineID(from: notification) else { continue }
            openNotificationMedicineDetails(for: medicineID)
        }
    }

    /// Opens the details popup for the medicine selected from a notification.
    private func openNotificationMedicineDetails(for medicineID: UUID) {
        if store.medicines.contains(where: { $0.id == medicineID }) {
            notificationMedicineID = medicineID
        } else {
            validationMessage = "This medicine is no longer available."
        }
    }

    /// Deletes one medicine and shows any disk-write failure instead of hiding it.
    @discardableResult
    private func deleteMedicine(_ medicine: Medicine) async -> Bool {
        do {
            try await store.delete(medicine)
            validationMessage = nil
            return true
        } catch {
            validationMessage = "Could not delete medicine: \(error.localizedDescription)"
            return false
        }
    }

    /// Friendly banner shown at the top of the form.
    ///
    /// This gives the app a lighter, less default-looking first impression without
    /// changing the form workflow below it.
    private var headerPanel: some View {
        HStack(spacing: 14) {
            Image(systemName: "pills.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(PillEyePalette.coral)

            VStack(alignment: .leading, spacing: 4) {
                Text("Track my Meds")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(PillEyePalette.ink)
                Text("Scan labels, save dates, and let PillEye remind you before expiry.")
                    .font(.subheadline)
                    .foregroundStyle(PillEyePalette.ink.opacity(0.72))
            }
        }
        .padding(.vertical, 10)
    }

    /// Opens the manual date popup and preloads it with the current date value if one exists.
    private func openManualDatePopup(for target: ManualDateTarget) {
        switch target {
        case .manufacturing:
            manualDateDraft = manufacturingDate ?? Date()
        case .expiry:
            manualDateDraft = expiryDate ?? Date()
        }
        manualDateTarget = target
    }

    /// Opens the saved-medicine edit popup.
    ///
    /// The draft mirrors the full medicine even though only the reminder lead is editable today.
    /// That keeps this popup ready for future name/date editing without changing the
    /// save pipeline.
    private func openMedicineEditPopup(for medicine: Medicine) {
        medicineEditDraft = MedicineEditDraft(medicine: medicine)
    }

    /// Center popup used for manually selecting a date.
    ///
    /// This is an overlay instead of a bottom sheet, so it appears in the middle of the
    /// phone and keeps the main screen visible behind a dimmed background.
    private func manualDatePopup(for target: ManualDateTarget) -> some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture {
                    manualDateTarget = nil
                }

            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(target.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PillEyePalette.deepTeal)
                    Text("Choose a date")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PillEyePalette.blue)
                }

                DatePicker(
                    target.pickerTitle,
                    selection: $manualDateDraft,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(PillEyePalette.teal)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        manualDateTarget = nil
                    }
                    .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.blue, prominence: .secondary, minHeight: 40))

                    Button("Okay") {
                        saveManualDate(for: target)
                    }
                    .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.coral, minHeight: 40))
                }
            }
            .padding(20)
            .frame(maxWidth: 310)
            .background(PillEyePalette.popupBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PillEyePalette.mint, lineWidth: 2)
            }
            .shadow(color: PillEyePalette.deepTeal.opacity(0.22), radius: 20, x: 0, y: 10)
            .fontDesign(.rounded)
        }
    }

    /// Center popup shown when the user taps an expiry notification.
    ///
    /// It uses the same colors as the main screen and exposes only the two requested
    /// actions: Delete removes this medicine, Cancel closes the popup.
    private func medicineDetailsPopup(for medicine: Medicine) -> some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "pills.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(PillEyePalette.coral)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(medicine.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(PillEyePalette.deepTeal)
                        Text(medicine.isExpired ? "Expired medicine" : "Expiry reminder")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PillEyePalette.blue)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    detailRow(title: "Manufacturing", value: medicine.manufacturingDate.formatted(date: .abbreviated, time: .omitted))
                    detailRow(title: "Expiry", value: medicine.expiryDate.formatted(date: .abbreviated, time: .omitted))
                    detailRow(title: "Reminder", value: medicine.reminderDate.formatted(date: .abbreviated, time: .shortened))
                    detailRow(title: "Reminder lead", value: ReminderLeadOption.label(for: medicine.reminderLeadDays))
                }

                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        Task {
                            let didDelete = await deleteMedicine(medicine)
                            if didDelete {
                                notificationMedicineID = nil
                            }
                        }
                    } label: {
                        Label("Delete", systemImage: "trash.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.coral, minHeight: 42))

                    Button {
                        notificationMedicineID = nil
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.blue, prominence: .secondary, minHeight: 42))
                }
            }
            .padding(20)
            .frame(maxWidth: 330)
            .background(PillEyePalette.popupBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PillEyePalette.mint, lineWidth: 2)
            }
            .shadow(color: PillEyePalette.deepTeal.opacity(0.22), radius: 20, x: 0, y: 10)
            .fontDesign(.rounded)
        }
    }

    /// Center popup for editing saved medicine settings.
    ///
    /// Name and dates are shown as read-only details. Only the reminder lead can be changed in this
    /// version, then Save writes the update to disk and refreshes the notification.
    private func medicineEditPopup(for draft: MedicineEditDraft) -> some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Reminder")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PillEyePalette.deepTeal)
                    Text(draft.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(PillEyePalette.coral)
                }

                VStack(alignment: .leading, spacing: 10) {
                    detailRow(title: "Manufacturing", value: draft.manufacturingDate.formatted(date: .abbreviated, time: .omitted))
                    detailRow(title: "Expiry", value: draft.expiryDate.formatted(date: .abbreviated, time: .omitted))
                }

                Picker("Remind before expiry", selection: Binding(
                    get: { medicineEditDraft?.reminderLeadDays ?? draft.reminderLeadDays },
                    set: { medicineEditDraft?.reminderLeadDays = $0 }
                )) {
                    ForEach(ReminderLeadOption.allDays, id: \.self) { days in
                        Text(ReminderLeadOption.label(for: days)).tag(days)
                    }
                }
                .pickerStyle(.menu)
                .tint(PillEyePalette.teal)

                HStack(spacing: 12) {
                    Button {
                        medicineEditDraft = nil
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.blue, prominence: .secondary, minHeight: 42))

                    Button {
                        saveMedicineEdit()
                    } label: {
                        Label("Save", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.coral, minHeight: 42))
                }
            }
            .padding(20)
            .frame(maxWidth: 330)
            .background(PillEyePalette.popupBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PillEyePalette.mint, lineWidth: 2)
            }
            .shadow(color: PillEyePalette.deepTeal.opacity(0.22), radius: 20, x: 0, y: 10)
            .fontDesign(.rounded)
        }
    }

    /// Saves the edited reminder lead time for an existing medicine.
    private func saveMedicineEdit() {
        guard let medicineEditDraft else { return }

        Task {
            do {
                try await store.update(
                    medicineID: medicineEditDraft.id,
                    changes: MedicineUpdate(reminderLeadDays: medicineEditDraft.reminderLeadDays)
                )
                self.medicineEditDraft = nil
                validationMessage = nil
            } catch {
                validationMessage = error.localizedDescription
            }
        }
    }

    /// Transient center card confirming a medicine was saved.
    ///
    /// Unlike the modal popups, there is no dimmed backdrop and touches pass straight
    /// through, so the user can keep working while the card dissolves on its own.
    private func saveConfirmationCard(for medicine: Medicine) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(PillEyePalette.teal)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved!")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PillEyePalette.deepTeal)
                    Text(medicine.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(PillEyePalette.coral)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                detailRow(title: "Manufacturing", value: medicine.manufacturingDate.formatted(date: .abbreviated, time: .omitted))
                detailRow(title: "Expiry", value: medicine.expiryDate.formatted(date: .abbreviated, time: .omitted))
                detailRow(title: "Reminder", value: "\(ReminderLeadOption.label(for: medicine.reminderLeadDays)) before expiry")
            }
        }
        .padding(18)
        .frame(maxWidth: 310)
        .background(PillEyePalette.popupBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PillEyePalette.mint, lineWidth: 2)
        }
        .shadow(color: PillEyePalette.deepTeal.opacity(0.22), radius: 20, x: 0, y: 10)
        .fontDesign(.rounded)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("saveConfirmationCard")
    }

    /// One title/value line inside the medicine notification popup.
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PillEyePalette.deepTeal)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(PillEyePalette.blue)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Handles the backup file picked in the Files browser.
    ///
    /// When medicines already exist, the import waits for the user to confirm replacing
    /// them. Importing into an empty list proceeds immediately.
    private func handleBackupSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let data = try readBackupFile(at: url)
                if store.medicines.isEmpty {
                    Task { await importBackup(data) }
                } else {
                    pendingImportData = data
                }
            } catch {
                backupMessage = "Could not read that file. Choose a MedXpiryTracker backup."
            }
        case .failure:
            backupMessage = "Could not open the selected file."
        }
    }

    /// Reads a picked file, which may live outside the app sandbox (iCloud Drive, AirDrop inbox, ...).
    private func readBackupFile(at url: URL) throws -> Data {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }

    /// Replaces the saved medicines with the backup contents and reschedules reminders.
    private func importBackup(_ data: Data) async {
        do {
            try await store.importData(data)
            let count = store.medicines.count
            backupMessage = "Imported \(count) medicine\(count == 1 ? "" : "s")."
        } catch {
            backupMessage = "Import failed. That file is not a valid MedXpiryTracker backup."
        }
    }

    /// Saves the manually selected date into the correct field.
    ///
    /// The dropdown then advances to the other date field, so entering both dates
    /// does not require changing the selection by hand.
    private func saveManualDate(for target: ManualDateTarget) {
        switch target {
        case .manufacturing:
            manufacturingDate = manualDateDraft
        case .expiry:
            expiryDate = manualDateDraft
        }
        revalidateDateOrder()
        activeDateField = target.other
        manualDateTarget = nil
    }

    /// Recomputes the cross-field validation message after either date changes.
    ///
    /// Uses the same wording as `MedicineValidationError.expiryNotAfterManufacturing`, so
    /// the user sees one consistent message whether the rule fails while entering dates
    /// or while saving. While only one date is set, there is nothing to compare yet.
    private func revalidateDateOrder() {
        if let manufacturingDate, let expiryDate, expiryDate <= manufacturingDate {
            validationMessage = "Expiry date must be after the manufacturing date."
        } else {
            validationMessage = nil
        }
    }

    /// The attached photo as a preview image, or `nil` when none is attached yet.
    private var pendingPhotoPreview: UIImage? {
        pendingPhotoData.flatMap(UIImage.init(data:))
    }

    /// Row for attaching one photo of the medicine before saving.
    ///
    /// Shows a small preview once attached. The button opens a chooser offering the
    /// camera (still photos only — never Live Photos) and the photo library.
    private var photoAttachmentRow: some View {
        HStack(spacing: 12) {
            if let preview = pendingPhotoPreview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(PillEyePalette.mint, lineWidth: 1.5)
                    }
                    .accessibilityLabel("Attached medicine photo")
            }

            Button {
                showingPhotoOptions = true
            } label: {
                Label(
                    pendingPhotoData == nil ? "Add photo" : "Change photo",
                    systemImage: pendingPhotoData == nil ? "photo.badge.plus" : "photo"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.teal, prominence: .secondary))
            .accessibilityIdentifier("addPhotoButton")

            if pendingPhotoData != nil {
                Button("Remove") {
                    pendingPhotoData = nil
                }
                .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.coral, prominence: .secondary))
                .accessibilityIdentifier("removePhotoButton")
            }
        }
        .confirmationDialog("Medicine photo", isPresented: $showingPhotoOptions) {
            Button("Take Photo") {
                if CameraPhotoPicker.isCameraAvailable {
                    showingCameraCapture = true
                } else {
                    showingCameraUnavailableAlert = true
                }
            }
            Button("Choose From Library") {
                showingPhotoLibrary = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Camera Unavailable", isPresented: $showingCameraUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device does not have an available camera. You can still attach a photo by choosing from your library.")
        }
    }

    /// Loads the picked library item as still-image data for the form preview.
    private func loadPickedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                pendingPhotoData = data
            }
            photoPickerItem = nil
        }
    }

    /// The date currently targeted by the dropdown (manufacturing or expiry).
    private var activeDateValue: Date? {
        switch activeDateField {
        case .manufacturing:
            return manufacturingDate
        case .expiry:
            return expiryDate
        }
    }

    /// A single compact block that captures whichever date the dropdown selects.
    ///
    /// Layout, top to bottom:
    /// 1. "Date" + the Manufacturing/Expiry dropdown with Scan aligned beside it, so
    ///    choosing what to capture and scanning it sit on one line.
    /// 2. Equal-width Set/Change and Clear buttons, giving two large, tidy tap targets.
    /// 3. Mfg/Exp status chips that keep both captured dates visible at all times.
    private var dateEntryRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Date")
                    .fontWeight(.semibold)
                    .foregroundStyle(PillEyePalette.deepTeal)
                Spacer()
                // An explicitly empty label: inside a Form row, a menu picker still renders
                // its title text even with .labelsHidden(). VoiceOver still gets a name
                // through the accessibility label below.
                Picker(selection: $activeDateField) {
                    Text("Manufacturing").tag(ManualDateTarget.manufacturing)
                    Text("Expiry").tag(ManualDateTarget.expiry)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.menu)
                .fixedSize()
                .accessibilityLabel("Date to set")
                .tint(PillEyePalette.teal)
                .accessibilityIdentifier("dateFieldPicker")

                Button {
                    scannerMode = activeDateField == .manufacturing ? .manufacturingDate : .expiryDate
                    showingScanner = true
                } label: {
                    Label("Scan", systemImage: "text.viewfinder")
                }
                .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.teal, prominence: .secondary, minHeight: 34))
            }

            HStack(spacing: 8) {
                Button {
                    openManualDatePopup(for: activeDateField)
                } label: {
                    Text(activeDateValue == nil ? "Set Date" : "Change")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.blue, prominence: .secondary, minHeight: 38))

                Button {
                    clearDates()
                } label: {
                    Text("Clear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.coral, prominence: .secondary, minHeight: 38))
                .disabled(manufacturingDate == nil && expiryDate == nil)
                .accessibilityIdentifier("clearDatesButton")
            }

            HStack(spacing: 10) {
                dateSummaryChip(title: "Mfg", date: manufacturingDate)
                dateSummaryChip(title: "Exp", date: expiryDate)
            }
        }
        .padding(.vertical, 2)
    }

    /// A plain "Mfg: … / Exp: …" status line keeping both captured dates visible.
    ///
    /// Deliberately undecorated — no capsule, fill, or border — so it reads as passive
    /// status text rather than another tappable button. A filled date shows a teal
    /// checkmark; an empty one shows a coral warning icon and a red dash.
    private func dateSummaryChip(title: String, date: Date?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: date == nil ? "calendar.badge.exclamationmark" : "calendar.badge.checkmark")
                .font(.caption2)
                .foregroundStyle(date == nil ? PillEyePalette.coral : PillEyePalette.teal)
            Text("\(title):")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PillEyePalette.deepTeal.opacity(0.75))
            Text(date?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                .font(.caption.weight(date == nil ? .bold : .semibold))
                .foregroundStyle(date == nil ? PillEyePalette.coral : PillEyePalette.deepTeal)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Clears both captured dates so the user can start the date entry over.
    private func clearDates() {
        manufacturingDate = nil
        expiryDate = nil
        activeDateField = .manufacturing
        revalidateDateOrder()
    }

    /// Validates and saves the current form values.
    ///
    /// If the store throws an error, the message is shown in the form instead of saving.
    private func saveMedicine() async {
        validationMessage = nil

        guard let manufacturingDate else {
            validationMessage = "Set the manufacturing date."
            return
        }

        guard let expiryDate else {
            validationMessage = "Set the expiry date."
            return
        }

        do {
            let medicine = try await store.save(
                name: medicineName,
                manufacturingDate: manufacturingDate,
                expiryDate: expiryDate,
                reminderLeadDays: reminderLeadDays,
                photoData: pendingPhotoData
            )
            resetForm()
            showSaveConfirmation(for: medicine)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    /// Shows the transient saved-medicine confirmation, then dissolves it away.
    ///
    /// The card fades in with a small spring, stays up long enough to read, and fades
    /// out on its own. If another save happens meanwhile, the newer confirmation wins
    /// and this one skips its dismissal.
    private func showSaveConfirmation(for medicine: Medicine) {
        withAnimation(.spring(duration: 0.35)) {
            savedConfirmation = medicine
        }

        Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard savedConfirmation?.id == medicine.id else { return }
            withAnimation(.easeOut(duration: 0.8)) {
                savedConfirmation = nil
            }
        }
    }

    /// Resets the input form after a successful save.
    private func resetForm() {
        medicineName = ""
        manufacturingDate = nil
        expiryDate = nil
        pendingPhotoData = nil
    }

    /// Receives the user's confirmed text selection from the scanner.
    ///
    /// Name scanning returns selected text. Date scanning returns exactly one selected
    /// date string, which is parsed and applied to the correct date field.
    private func applyCapturedTexts(_ texts: [String]) {
        switch scannerMode {
        case .name:
            medicineName = (texts.first ?? "").localizedCapitalized
            validationMessage = nil
        case .manufacturingDate:
            applyScannedManufacturingDate(from: texts.first)
        case .expiryDate:
            applyScannedExpiryDate(from: texts.first)
        }

        showingScanner = false
    }

    /// Parses and applies a scanned manufacturing date.
    private func applyScannedManufacturingDate(from text: String?) {
        guard let text, let date = MedicineDateParser.firstDate(from: text) else {
            validationMessage = "Could not read a valid manufacturing date. You can still edit it manually."
            return
        }

        manufacturingDate = date
        revalidateDateOrder()
        activeDateField = .expiry
    }

    /// Parses and applies a scanned expiry date.
    private func applyScannedExpiryDate(from text: String?) {
        guard let text, let date = MedicineDateParser.firstDate(from: text) else {
            validationMessage = "Could not read a valid expiry date. You can still edit it manually."
            return
        }

        expiryDate = date
        revalidateDateOrder()
        activeDateField = .manufacturing
    }

    /// Full-screen overlay shown once on first launch explaining the camera scanning feature.
    private var cameraOnboardingOverlay: some View {
        ZStack {
            Color.black.opacity(0.40)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(PillEyePalette.teal)

                VStack(spacing: 8) {
                    Text("Capture Labels with Your Camera")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PillEyePalette.deepTeal)
                        .multilineTextAlignment(.center)

                    Text("PillEye uses your device's back camera to read medicine names and dates directly from the label. Tap a camera button, point at the text, select what you need, and the field fills in automatically — no typing required.")
                        .font(.subheadline)
                        .foregroundStyle(PillEyePalette.ink.opacity(0.80))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                Button {
                    hasSeenOnboarding = true
                } label: {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DimensionalButtonStyle(fill: PillEyePalette.teal, minHeight: 46))
                .accessibilityIdentifier("onboardingGetStartedButton")
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(PillEyePalette.popupBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(PillEyePalette.mint, lineWidth: 2)
            }
            .shadow(color: PillEyePalette.deepTeal.opacity(0.28), radius: 24, x: 0, y: 12)
            .fontDesign(.rounded)
        }
    }

}

/// Light, friendly colors used by the PillEye interface.
///
/// Grouping colors here keeps styling consistent and easier to change later.
nonisolated enum PillEyePalette {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.94, green: 0.99, blue: 0.97),
            Color(red: 0.98, green: 0.97, blue: 1.00),
            Color(red: 1.00, green: 0.97, blue: 0.94)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let popupBackground = LinearGradient(
        colors: [
            Color(red: 0.98, green: 1.00, blue: 0.99),
            Color(red: 0.96, green: 0.98, blue: 1.00)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let formRowBackground = Color(red: 0.985, green: 1.00, blue: 0.99)
    static let mint = Color(red: 0.82, green: 0.96, blue: 0.91)
    static let teal = Color(red: 0.00, green: 0.58, blue: 0.58)
    static let deepTeal = Color(red: 0.00, green: 0.36, blue: 0.42)
    static let coral = Color(red: 0.96, green: 0.36, blue: 0.33)
    static let blue = Color(red: 0.25, green: 0.50, blue: 0.92)
    static let ink = Color(red: 0.12, green: 0.18, blue: 0.24)

    // Status colors for the saved-medicines filter: All = green, Expiring = orange,
    // Expired = red. Red reads as an alert color consistent with `coral` warnings.
    static let filterGreen = Color.green
    static let filterOrange = Color.orange
    static let filterRed = Color.red
}

/// Identifies which date field is being edited in the manual date popup.
private enum ManualDateTarget: Hashable, Identifiable {
    case manufacturing
    case expiry

    var id: Self { self }

    /// The opposite date field, used to advance the dropdown after one date is captured.
    var other: ManualDateTarget {
        self == .manufacturing ? .expiry : .manufacturing
    }

    var title: String {
        switch self {
        case .manufacturing:
            return "Manufacturing Date"
        case .expiry:
            return "Expiry Date"
        }
    }

    var pickerTitle: String {
        switch self {
        case .manufacturing:
            return "Select manufacturing date"
        case .expiry:
            return "Select expiry date"
        }
    }
}

/// Identifies what kind of text the scanner is currently expected to capture.
private enum ScannerMode {
    case name
    case manufacturingDate
    case expiryDate

    /// Title shown at the top of the scanner sheet.
    var title: String {
        switch self {
        case .name:
            return "Scan Name"
        case .manufacturingDate:
            return "Scan Manufacturing Date"
        case .expiryDate:
            return "Scan Expiry Date"
        }
    }

    /// Short user guidance shown inside the scanner sheet.
    var instructions: String {
        switch self {
        case .name:
            return "Place the medicine name inside the rectangle, tap the best detected text, then press OK."
        case .manufacturingDate:
            return "Place the manufacturing date inside the rectangle. Tap the correct detected date, then press Capture."
        case .expiryDate:
            return "Place the expiry date inside the rectangle. Tap the correct detected date, then press Capture."
        }
    }

    /// Controls whether the scanner should capture general text or one selected date value.
    var captureMode: TextScannerCaptureMode {
        switch self {
        case .name:
            return .manualText
        case .manufacturingDate, .expiryDate:
            return .singleDate
        }
    }
}

/// Draft values used by the saved-medicine edit popup.
///
/// The fields include name and dates even though they are read-only today. If those
/// become editable later, the popup can bind to this same draft and send one
/// `MedicineUpdate` to the store.
private struct MedicineEditDraft: Identifiable {
    let id: UUID
    var name: String
    var manufacturingDate: Date
    var expiryDate: Date
    var reminderLeadDays: Int

    init(medicine: Medicine) {
        id = medicine.id
        name = medicine.name
        manufacturingDate = medicine.manufacturingDate
        expiryDate = medicine.expiryDate
        reminderLeadDays = medicine.reminderLeadDays
    }
}

#Preview {
    ContentView(store: MedicineStore(notificationScheduler: PreviewNotificationScheduler()))
}

/// Fake scheduler used only by the SwiftUI preview.
///
/// This avoids asking for real notification permissions when Xcode renders previews.
private struct PreviewNotificationScheduler: NotificationScheduling {
    func scheduleExpiryReminder(for medicine: Medicine) async throws {}
    func cancelReminder(for medicineID: UUID) async {}
}
