function [frames, nvols, header] = get_nii_frames(nii_file)
%GET_NII_FRAMES Return all frame references for a 4D NIfTI using spm_vol.

if exist(nii_file, 'file') ~= 2
    error('get_nii_frames:MissingFile', ...
        'NIfTI file does not exist: %s', nii_file);
end

header = spm_vol(nii_file);
nvols = numel(header);
if nvols < 2
    error('get_nii_frames:Not4D', ...
        'Expected a 4D functional NIfTI with multiple frames: %s', nii_file);
end

frames = cell(nvols, 1);
for i = 1:nvols
    frames{i} = sprintf('%s,%d', nii_file, i);
end
end
