function cfg = local_config()

repo_root = fileparts(fileparts(mfilename('fullpath')));

cfg = struct();

cfg.run_dicom_conversion = true;
cfg.dicom_root = fullfile(repo_root, 'data', 'dicom');
cfg.converted_root = fullfile(repo_root, 'data', 'converted');
cfg.output_root = fullfile(repo_root, 'data', 'derivatives', 'spm_preproc');
cfg.log_root = fullfile(repo_root, 'logs');

cfg.dcm2niix_path = 'C:\MRIcroGL\Resources\dcm2niix.exe';
cfg.dcm2niix_compress = false;
cfg.overwrite_converted = false;
cfg.dcm2niix_filename_pattern = '%f_%p_%t_%s';

cfg.subjects = {'sub-01'};
cfg.sessions = {};

cfg.func_dir = 'func';
cfg.anat_dir = 'anat';

cfg.func_pattern = '*FACE*1*.nii';
cfg.json_pattern = '*FACE*1*.json';
cfg.t1_pattern = '*T1*.nii';

cfg.voxel_size = [3 3 3];
cfg.smooth_fwhm = [6 6 6];

end