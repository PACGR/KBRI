function cfg = config_template()
%CONFIG_TEMPLATE Generic defaults for SPM fMRI preprocessing automation.
%
% Copy this file to config/local_config.m or another local file and pass it
% to preprocess_all. Keep local configs out of version control.

repo_root = fileparts(fileparts(mfilename('fullpath')));

cfg = struct();

cfg.run_dicom_conversion = false;
cfg.dicom_root = fullfile(repo_root, 'data', 'dicom');
cfg.raw_root = fullfile(repo_root, 'data', 'raw');
cfg.converted_root = fullfile(repo_root, 'data', 'converted');
cfg.output_root = fullfile(repo_root, 'data', 'derivatives', 'spm_preproc');
cfg.log_root = fullfile(repo_root, 'logs');

cfg.dcm2niix_path = 'dcm2niix';
cfg.dcm2niix_compress = false;
cfg.overwrite_converted = false;
cfg.dcm2niix_filename_pattern = '%f_%p_%t_%s';

% Subject discovery. Leave cfg.subjects empty to discover folders using
% cfg.subject_pattern. For a KIM/CHI-style DICOM tree, set:
%   cfg.layout = 'subject_run_folders';
%   cfg.dicom_root = fullfile(repo_root, 'data', 'dicom');
%   cfg.run_dicom_conversion = true;
cfg.subject_pattern = '*';
cfg.subjects = {};
cfg.exclude_subject_dirs = {'converted', 'derivatives', 'logs', '.', '..'};
cfg.sessions = {};

% Preferred real-world layout:
% data/dicom/<subject>/<run>/ and data/dicom/<subject>/t1/
% converts to:
% data/converted/<subject>/func/<run>/ and data/converted/<subject>/anat/
cfg.layout = 'subject_run_folders';
cfg.run_dir_patterns = {'face_run*'};
cfg.t1_dir_pattern = 't1';

% BIDS-like compatibility fields. Set cfg.layout = 'bids' for
% data/raw/sub-01/func and data/raw/sub-01/anat style inputs.
cfg.func_dir = 'func';
cfg.anat_dir = 'anat';
cfg.func_pattern = '*.nii';
cfg.json_pattern = '*.json';
cfg.t1_pattern = '*.nii';

cfg.voxel_size = [3 3 3];
cfg.smooth_fwhm = [6 6 6];

end
