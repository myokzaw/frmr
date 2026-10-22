---
name: v5.1 backend
description: Continue to diary, DiaryEntry.rollPhotoID live link, RollDeletion, legacy shims awaiting frontend
type: project
---
- Linked entry mirrors roll photoPath + look (RollViewModel.update syncs); no image copy. keepEntry copies file to Photos/, snapshots look, clears link.
- CameraViewModel keeps LEGACY shims (Mode.diary alias = .photo, selectDiaryMode, captureForDiary, review, isReviewPresented, confirmReview, retake, beginReview) + DiaryReviewViewModel file until frontend deletes CameraView branches/DiaryReviewView; then delete shims.
- scripts/test.sh suite takes struct names, not file names; sim may be Busy on first run (retry --no-build).
