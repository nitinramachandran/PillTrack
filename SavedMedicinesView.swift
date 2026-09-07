import PhotosUI
import SwiftUI

/// The expiry-status filter applied to the saved-medicines list.
///
/// `All` shows every medicine, `expiring` shows medicines that have not yet expired and
/// expire within the next `Medicine.expiringSoonWindowDays` days, and `expired` shows
/// medicines whose expiry date has already passed. The raw values are used as stable
/// identifiers in the picker.
nonisolated enum MedicineFilter: String, CaseIterable, Identifiable {
    case all
    case expiring
    case expired

    var id: String { rawValue }

    /// User-facing label for the filter option.
    var label: String {
        switch self {
        case .all:
            return "All"
        case .expiring:
            return "Expiring"
        case .expired:
            return "Expired"
        }
    }

    /// Accessibility identifier for the filter option's tappable control.
    var accessibilityIdentifier: String {
        switch self {
        case .all:
            return "filterAll"
        case .expiring:
            return "filterExpiring"
        case .expired:
            return "filterExpired"
        }
    }

    /// The label color for this filter: All = green, Expiring = orange, Expired = red.
    var color: Color {
        switch self {
        case .all:
            return PillEyePalette.filterGreen
        case .expiring:
            return PillEyePalette.filterOrange
        case .expired:
            return PillEyePalette.filterRed
        }
    }

    /// Returns `true` when the given medicine belongs in this filter.
    ///
    /// The optional `now` parameter keeps one consistent reference time across a whole
    /// list evaluation and makes the filter unit-testable with fixed dates.
    func includes(_ medicine: Medicine, now: Date = Date()) -> Bool {
        switch self {
        case .all:
            return true
        case .expiring:
            return medicine.isExpiringSoon(now: now)
        case .expired:
            return medicine.expiryDate < now
        }
    }
}

/// Popup listing saved medicines with a three-way expiry-status filter.
///
/// Presented as a sheet because the list is scrollable and needs swipe actions for
/// edit and delete. Styling mirrors the app's other popups (rounded font, palette
/// colors, mint accents).
struct SavedMedicinesView: View {
    let store: MedicineStore
    /// Called when the user chooses to edit a medicine; the parent opens its edit popup.
    let onEdit: (Medicine) -> Void
    /// Called when the user deletes a medicine; the parent forwards this to the store.
    let onDelete: (Medicine) async -> Void
    let onClose: () -> Void

    @State private var filter: MedicineFilter = .expiring
    @State private var expandedPhoto: ExpandedMedicinePhoto?
    @State private var photoTargetMedicine: Medicine?
    @State private var showingPhotoSourceOptions = false
    @State private var showingCameraCapture = false
    @State private var showingPhotoLibrary = false
    @State private var showingCameraUnavailableAlert = false
    @State private var photoPickerItem: PhotosPickerItem?

    /// Medicines matching the currently selected filter.
    ///
    /// One `now` is captured per evaluation so every medicine in the list is judged
    /// against the same instant. Reading `photoVersion` makes Observation re-render the
    /// list when a photo is attached, since that changes disk state, not `medicines`.
    private var filteredMedicines: [Medicine] {
        _ = store.photoVersion
        let now = Date()
        return store.medicines.filter { filter.includes($0, now: now) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterPicker
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                listContent
            }
            .background(PillEyePalette.background)
            .navigationTitle("Saved Medicines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                        .accessibilityIdentifier("savedMedicinesDoneButton")
                }
            }
            .toolbarBackground(PillEyePalette.mint, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .sheet(item: $expandedPhoto) { photo in
                ExpandedMedicinePhotoView(photo: photo) {
                    expandedPhoto = nil
                }
            }
            .confirmationDialog(
                "Add photo for \(photoTargetMedicine?.name ?? "medicine")",
                isPresented: $showingPhotoSourceOptions
            ) {
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
                Button("Cancel", role: .cancel) {
                    photoTargetMedicine = nil
                }
            }
            .alert("Camera Unavailable", isPresented: $showingCameraUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This device does not have an available camera. You can still attach a photo by choosing from your library.")
            }
            .sheet(isPresented: $showingCameraCapture) {
                CameraPhotoPicker(
                    onCapture: { data in
                        attachPhoto(data)
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
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        attachPhoto(data)
                    }
                    photoPickerItem = nil
                }
            }
        }
        .fontDesign(.rounded)
        .tint(PillEyePalette.teal)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
    }

    /// Stores the chosen photo for the medicine the user tapped Add photo on.
    private func attachPhoto(_ data: Data) {
        guard let medicine = photoTargetMedicine else { return }
        Task {
            try? await store.attachPhoto(data, to: medicine)
            photoTargetMedicine = nil
        }
    }

    /// The three radio-style filter options, each tinted by its status color.
    private var filterPicker: some View {
        HStack(spacing: 10) {
            ForEach(MedicineFilter.allCases) { option in
                Button {
                    filter = option
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: filter == option ? "circle.inset.filled" : "circle")
                        Text(option.label)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(option.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(filter == option ? option.color.opacity(0.14) : Color.white.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(option.color.opacity(filter == option ? 0.9 : 0.35), lineWidth: filter == option ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(option.accessibilityIdentifier)
                .accessibilityAddTraits(filter == option ? [.isSelected] : [])
            }
        }
    }

    /// The list, the empty-store state, or the empty-filter state.
    @ViewBuilder
    private var listContent: some View {
        if store.medicines.isEmpty {
            ContentUnavailableView(
                "No medicines saved",
                systemImage: "pills",
                description: Text("Add medicine details on the main screen to schedule an expiry reminder.")
            )
            .accessibilityIdentifier("savedMedicinesEmptyState")
        } else if filteredMedicines.isEmpty {
            ContentUnavailableView(
                "Nothing here",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("No medicines match the \(filter.label) filter.")
            )
            .accessibilityIdentifier("savedMedicinesNoMatches")
        } else {
            List {
                ForEach(filteredMedicines) { medicine in
                    MedicineRow(
                        medicine: medicine,
                        thumbnailURL: store.thumbnailURL(for: medicine),
                        onPhotoTap: {
                            guard let imageURL = store.imageURL(for: medicine) else { return }
                            expandedPhoto = ExpandedMedicinePhoto(
                                id: medicine.id,
                                name: medicine.name,
                                imageURL: imageURL
                            )
                        },
                        onAddPhoto: medicine.isExpired ? nil : {
                            photoTargetMedicine = medicine
                            showingPhotoSourceOptions = true
                        }
                    )
                        .listRowBackground(PillEyePalette.formRowBackground)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await onDelete(medicine) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                onEdit(medicine)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(PillEyePalette.blue)
                        }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

/// One row in the saved medicines list.
///
/// The medicine name is tinted by its own status: expired = red, expiring within 60 days =
/// orange, otherwise green — matching the filter categories so colors stay consistent under "All".
/// A medicine with a photo shows a small tappable thumbnail that opens the full image.
struct MedicineRow: View {
    let medicine: Medicine
    var thumbnailURL: URL?
    var onPhotoTap: (() -> Void)?
    var onAddPhoto: (() -> Void)?

    /// Status color for the medicine name, matching the three filter categories.
    private var nameColor: Color {
        if medicine.isExpired {
            return PillEyePalette.filterRed
        }
        if medicine.isExpiringSoon() {
            return PillEyePalette.filterOrange
        }
        return PillEyePalette.filterGreen
    }

    /// Shows the medicine name, dates, reminder time, expired status, and photo thumbnail.
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let thumbnailURL {
                Button {
                    onPhotoTap?()
                } label: {
                    MedicinePhotoThumbnail(url: thumbnailURL)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show photo of \(medicine.name)")
                .accessibilityIdentifier("medicinePhotoThumbnail")
            } else if let onAddPhoto {
                Button(action: onAddPhoto) {
                    Image(systemName: "photo.badge.plus")
                        .font(.caption)
                        .foregroundStyle(PillEyePalette.teal)
                        .frame(width: 44, height: 44)
                        .background(PillEyePalette.mint.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(PillEyePalette.teal.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add photo for \(medicine.name)")
                .accessibilityIdentifier("addMedicinePhotoButton")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(medicine.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(nameColor)
                    Spacer()
                    if medicine.isExpired {
                        Text("Expired")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PillEyePalette.filterRed)
                    }
                }

                Text("Mfg: \(medicine.manufacturingDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(PillEyePalette.blue)
                Text("Exp: \(medicine.expiryDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(PillEyePalette.blue)
                Text("Reminder: \(medicine.reminderDate.formatted(date: .abbreviated, time: .shortened)) (\(ReminderLeadOption.label(for: medicine.reminderLeadDays)) before expiry)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PillEyePalette.deepTeal)
            }
        }
        .padding(.vertical, 6)
    }
}

/// A medicine photo selected for full-size viewing.
struct ExpandedMedicinePhoto: Identifiable {
    let id: UUID
    let name: String
    let imageURL: URL
}

/// Small async-loaded thumbnail for a medicine row.
///
/// Loads the tiny thumbnail file off the main actor so list scrolling stays smooth.
private struct MedicinePhotoThumbnail: View {
    let url: URL

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(PillEyePalette.teal.opacity(0.5))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PillEyePalette.mint, lineWidth: 1)
        }
        .task(id: url) {
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: url.path)
            }.value
        }
    }
}

/// Full-size photo viewer opened by tapping a row thumbnail.
///
/// Loads the stored display image asynchronously and shows it fitted on a dark
/// backdrop. Tapping anywhere (or Done) closes the sheet.
private struct ExpandedMedicinePhotoView: View {
    let photo: ExpandedMedicinePhoto
    let onClose: () -> Void

    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Photo of \(photo.name)")
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
            .navigationTitle(photo.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                        .accessibilityIdentifier("expandedPhotoDoneButton")
                }
            }
            .toolbarBackground(PillEyePalette.mint, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .fontDesign(.rounded)
        .task(id: photo.imageURL) {
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: photo.imageURL.path)
            }.value
        }
    }
}
