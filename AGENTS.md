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