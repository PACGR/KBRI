function cfg = config_template()
%CONFIG_TEMPLATE User-editable defaults for SPM fMRI preprocessing.
%
% Copy this file to a local config file and pass it to preprocess_all:
%   preprocess_all('config/my_config.m')

repo_root = fileparts(fileparts(mfilename('fullpath')));

cfg = struct();

% DICOM conversion inputs/outputs can live outside this repository. The
% converted_root defaults to the NIfTI/JSON input root used by preprocessing.
cfg.dicom_root = fullfile(repo_root, 'data', 'dicom');
cfg.converted_root = fullfile(repo_root, 'data', 'converted');
cfg.dcm2niix_path = 'dcm2niix';
cfg.dcm2niix_compress = false;
cfg.run_dicom_conversion = false;
cfg.overwrite_converted = false;

% Raw NIfTI/JSON data can live outside this repository. When
% cfg.run_dicom_conversion is true, preprocess_all reads from
% cfg.converted_root instead of cfg.raw_root.
cfg.raw_root = fullfile(repo_root, 'data', 'raw');
cfg.output_root = fullfile(repo_root, 'data', 'derivatives', 'spm_preproc');
cfg.log_root = fullfile(repo_root, 'logs');

% Leave empty to discover sub-* folders and ses-* folders automatically.
% Datasets without ses-* are treated as one "single_session" run per subject.
cfg.subjects = {};
cfg.sessions = {};

% BIDS-like defaults. The broad fallback patterns support dcm2niix outputs
% named with cfg.dcm2niix_filename_pattern inside separate func/anat folders.
cfg.func_dir = 'func';
cfg.anat_dir = 'anat';
cfg.func_pattern = '*FACE*1*.nii';
cfg.json_pattern = '*FACE*1*.json';
cfg.t1_pattern = '*T1*.nii';
cfg.dcm2niix_path = 'C:\Users\Park Junsang\Documents\MRIcroGL\Resources\dcm2niix.exe';
% SPM preprocessing defaults.
cfg.voxel_size = [3 3 3];
cfg.smooth_fwhm = [6 6 6];
end
