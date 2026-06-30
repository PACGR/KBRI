# AGENTS.md

## Project
This repository automates SPM fMRI preprocessing for multiple subjects and sessions.

## Environment
- Language: MATLAB
- Main dependency: SPM
- Input data: NIfTI functional images and JSON sidecars converted by dcm2niix.
- Do not overwrite raw NIfTI or JSON files.
- Do not commit raw neuroimaging data.
- Generated files should use SPM prefixes: a, r, w, s.

## Pipeline
Default preprocessing order:
1. Gunzip .nii.gz if needed
2. Slice Timing
3. Realign: Estimate & Reslice
4. Coregister: Estimate
5. Segment T1
6. Normalise: Write
7. Smooth

## Data rules
- Functional images are 4D NIfTI.
- Always select all frames, not only the first volume.
- Derive TR from JSON RepetitionTime.
- Derive number of slices from JSON SliceTiming length when available.
- Derive slice order by sorting SliceTiming in ascending order.
- Use the reference slice closest to the middle acquisition time.
- Use the T1 anatomical image for segmentation.
- Use y_T1.nii as the forward deformation field for functional normalization.

## Default parameters
- TA = TR - TR/nslices
- Realign output: All Images + Mean Image
- Coregister: Estimate only
- Normalise voxel size: [3 3 3]
- Functional interpolation: 4th Degree B-Spline
- Smooth FWHM: [6 6 6]

## Quality checks
After each subject/session:
- Confirm output files exist.
- Confirm number of frames is preserved.
- Confirm rp_*.txt has nvols rows and 6 columns.
- Write a log file with subject, session, input files, parameters, and outputs.

## Coding style
- Prefer small functions over one long script.
- Separate configuration, file discovery, batch construction, execution, and QC.
- Add comments for SPM-specific assumptions.
- When making changes, explain which preprocessing step is affected.

## Data Layout Support

This project must support both BIDS-like subject names and arbitrary subject folder names.

Valid subject folder examples:
- sub-01
- sub-02
- KIM
- CHI
- PARK_JS

Do not require subject folders to start with `sub-*`.

Subject discovery rules:
- If `cfg.subjects` is provided, use only those subject folder names.
- Otherwise discover subject folders under `cfg.dicom_root` or `cfg.raw_root` using `cfg.subject_pattern`.
- Exclude non-subject folders listed in `cfg.exclude_subject_dirs`.
- Never rename, move, or modify original DICOM folders.

Supported DICOM layout:
```text
data/dicom/
  KIM/
    face_run1/
    face_run2/
    face_runN/
    t1/
  CHI/
    face_run1/
    face_run2/
    t1/

Run discovery rules:

Each functional run can be a subject-level folder such as face_run1, face_run2, etc.
The T1 anatomical folder is subject-level and should be reused for all runs of that subject.
Functional run folders are discovered using cfg.run_dir_patterns.
The anatomical folder is discovered using cfg.t1_dir_pattern.

Derivative output organization:

data/derivatives/spm_preproc/
  KIM/
    anat/
    func/
      face_run1/
      face_run2/
  CHI/
    anat/
    func/
      face_run1/

Converted NIfTI organization:

data/converted/
  KIM/
    anat/
    func/
      face_run1/
      face_run2/

Keep the preprocessing sequence unchanged:

DICOM conversion if enabled
Slice Timing
Realign: Estimate & Reslice
Coregister: Estimate
Segment T1
Normalise: Write
Smooth

Coregistration direction must remain:

Reference/fixed image: T1 anatomical image
Source/moved image: mean functional image
Other images: realigned functional frames

Segment must write forward deformation y_T1.nii for Normalise: Write.