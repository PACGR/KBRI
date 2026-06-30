function cfg = config_template()
%CONFIG_TEMPLATE User-editable defaults for SPM fMRI preprocessing.
%
% Copy this file to a local config file and pass it to preprocess_all:
%   preprocess_all('config/my_config.m')

repo_root = fileparts(fileparts(mfilename('fullpath')));

cfg = struct();

% Raw data can live outside this repository. The default is only a template.
cfg.raw_root = fullfile(repo_root, 'data', 'raw');
cfg.output_root = fullfile(repo_root, 'data', 'derivatives', 'spm_preproc');
cfg.log_root = fullfile(repo_root, 'logs');

% Leave empty to discover sub-* folders and ses-* folders automatically.
% Datasets without ses-* are treated as one "single_session" run per subject.
cfg.subjects = {};
cfg.sessions = {};

% BIDS-like defaults. Keep patterns narrow so ambiguous inputs fail clearly.
cfg.func_dir = 'func';
cfg.anat_dir = 'anat';
cfg.func_pattern = '*_bold.nii';
cfg.json_pattern = '*_bold.json';
cfg.t1_pattern = '*_T1w.nii';

% SPM preprocessing defaults.
cfg.voxel_size = [3 3 3];
cfg.smooth_fwhm = [6 6 6];
end
