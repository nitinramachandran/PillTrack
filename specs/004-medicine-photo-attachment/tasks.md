# Tasks: Medicine Photo Attachment

**Input**: `specs/004-medicine-photo-attachment/spec.md`
**Status**: Implemented

## Phase 1: Tests First
- [x] T001 Unit test: 3000×2000 photo downsamples to ≤1280 px long edge with smaller data
  (`imageProcessorDownscalesAndCompressesLargePhotos`).
- [x] T002 Unit test: save with photo stores it, delete removes it (`storeSavesAndDeletesMedicinePhoto`
  with `SpyImageStore`).
- [x] T003 Unit test: import deletes images only for medicines no longer present
  (`importDeletesImagesOnlyForRemovedMedicines`).

## Phase 2: Core
- [x] T004 `MedicineImageProcessor.downsampledJPEGData` — ImageIO thumbnailing (never decodes the
  full-size original), JPEG 0.7 (`Medicine Date Alerter/MedicineImageStore.swift`).
- [x] T005 `MedicineImageStoring` protocol + `MedicineImageStore` (Application Support/PillEye/Images,
  `<id>.jpg` @1280 px + `<id>-thumb.jpg` @240 px, atomic writes, complete file protection,
  processing off-main via `Task.detached`) + `NullMedicineImageStore` for tests/previews.
- [x] T006 `MedicineStore`: injected image store, `save(photoData:)`, delete removes the photo,
  import removes photos only for dropped IDs, `imageURL(for:)`/`thumbnailURL(for:)` accessors.

## Phase 3: UI
- [x] T007 `CameraPhotoPicker` (`Medicine Date Alerter/CameraPhotoPicker.swift`) —
  UIImagePickerController camera, still photos only; `isCameraAvailable` gates simulators.
- [x] T008 Add-form photo row (`addPhotoButton`/`removePhotoButton`): confirmation dialog with
  Take Photo / Choose From Library; PhotosPicker filter `.all(of: [.images, .not(.livePhotos)])`;
  preview thumbnail; photo cleared on successful save; kept when save fails.
- [x] T009 Saved Medicines rows show a 44 pt async-loaded thumbnail (`medicinePhotoThumbnail`);
  tap opens `ExpandedMedicinePhotoView` sheet (fitted image on black, tap or Done dismisses).

## Phase 4: Verify
- [x] T010 Build clean (no warnings); 29/29 tests pass; ContentView preview renders the photo row.

## Notes
- Backups remain JSON-only; photos are device-local attachments keyed by medicine UUID and are
  not transferred with export/import (documented in the spec edge cases).
