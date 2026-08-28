# Feature Specification: Medicine Photo Attachment

**Feature Branch**: `004-medicine-photo-attachment`
**Created**: 2026-08-27
**Status**: Implemented
**Input**: "Attach a photo of the medicine before saving it. Follow best practices for storing
captured images; show a tiny thumbnail in the Saved Medicines list; tapping it expands to a
bigger image. Manage large images — no Live Photos — and bring the file size down. Deleting a
medicine removes its image."

## User Scenarios & Testing *(mandatory)*

### Primary User Story
While filling the add form, the user attaches a photo of the medicine — taking one with the
camera or choosing a still image from their library — and sees a small preview. Saving stores
the photo with the record. In Saved Medicines, each medicine with a photo shows a tiny
thumbnail; tapping it opens the photo large. Deleting the medicine deletes its photo too.

### Acceptance Scenarios
1. **Given** the add form, **When** the user taps Add photo, **Then** they can take a photo or
   choose a still image (never a Live Photo) and see a preview with a way to remove it.
2. **Given** an attached photo, **When** the medicine is saved, **Then** the image is stored
   on-device, downscaled and compressed.
3. **Given** the Saved Medicines popup, **Then** medicines with photos show a small thumbnail;
   tapping the thumbnail expands the full image; tapping again (or Done) closes it.
4. **Given** a medicine with a photo is deleted, **Then** its image files are removed from disk.

### Edge Cases
- Camera unavailable (simulator / restricted): only the library option is offered.
- A photo attached but save fails (validation/duplicate): the photo stays attached to the form.
- A backup imported on a new phone has no image files: rows simply show no thumbnail (backups
  are JSON-only; images are device-local attachments).
- Very large source images (e.g. 48 MP) must not be decoded at full size into memory.

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: The add form MUST let the user attach one photo before saving — camera capture or
  photo-library selection restricted to still images (Live Photos excluded) — with preview and
  remove.
- **FR-002**: Saving MUST persist the image on-device: downscaled to at most 1280 px on the long
  edge, JPEG-compressed, plus a small thumbnail (~240 px) for lists. Downsampling MUST use
  ImageIO thumbnailing so the full-size original is never fully decoded into memory.
- **FR-003**: Images MUST live in the app sandbox (Application Support/PillEye/Images) with
  `.completeFileProtection`, named by the medicine's UUID.
- **FR-004**: The Saved Medicines list MUST show a small thumbnail for medicines with a photo;
  tapping it MUST present the full image in an expanded, dismissible view.
- **FR-005**: Deleting a medicine MUST delete its image and thumbnail. Importing a backup MUST
  delete images only for medicines that are no longer present (same-device restores keep them).

### Non-Functional Requirements
- **Privacy**: images never leave the device; no photo-library write access is requested
  (PhotosPicker runs out-of-process and needs no permission; camera reuses the existing usage
  description).
- **Testability**: image processing is a pure data→data function; the store depends on a
  `MedicineImageStoring` protocol so unit tests use a spy.
- **Compatibility**: the persisted `Medicine` JSON format is unchanged — images are referenced
  by medicine ID on disk, so old backups remain valid.

### Key Entities
- No model changes. New `MedicineImageStore` (files keyed by medicine UUID: `<id>.jpg`,
  `<id>-thumb.jpg`) behind a `MedicineImageStoring` protocol.

## Review & Acceptance Checklist
- [x] Live Photos explicitly excluded (`PHPickerFilter .not(.livePhotos)`; camera stills only)
- [x] Size management specified (1280 px / JPEG + 240 px thumbnail, ImageIO downsampling)
- [x] Deletion and import lifecycles specified
- [x] No persistence-format changes
