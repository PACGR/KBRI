function [matlabbatch, info] = make_preproc_batch(func_nii, t1_nii, func_json, cfg)
%MAKE_PREPROC_BATCH Build one SPM preprocessing batch.
%
% This constructs the default pipeline for one subject and one functional
% session: Slice Timing, Realign Estimate & Reslice, Coregister Estimate,
% Segment T1, Normalise Write, and Smooth.

if nargin < 4
    cfg = struct();
end
if ~isfield(cfg, 'voxel_size') || isempty(cfg.voxel_size)
    cfg.voxel_size = [3 3 3];
end
if ~isfield(cfg, 'smooth_fwhm') || isempty(cfg.smooth_fwhm)
    cfg.smooth_fwhm = [6 6 6];
end

json_info = read_func_json(func_json);
[func_scans, nvols, func_header] = get_nii_frames(func_nii);
if numel(func_header(1).dim) >= 3 && func_header(1).dim(3) ~= json_info.nslices
    error('make_preproc_batch:SliceCountMismatch', ...
        'JSON SliceTiming has %d slice(s), but NIfTI header has %d slice(s): %s', ...
        json_info.nslices, func_header(1).dim(3), func_nii);
end

matlabbatch = {};

% Slice timing uses dcm2niix SliceTiming values. SPM expects slice indices
% ordered by acquisition time, plus a reference slice index.
matlabbatch{1}.spm.temporal.st.scans = {func_scans};
matlabbatch{1}.spm.temporal.st.nslices = json_info.nslices;
matlabbatch{1}.spm.temporal.st.tr = json_info.TR;
matlabbatch{1}.spm.temporal.st.ta = json_info.TA;
matlabbatch{1}.spm.temporal.st.so = json_info.slice_order;
matlabbatch{1}.spm.temporal.st.refslice = json_info.reference_slice;
matlabbatch{1}.spm.temporal.st.prefix = 'a';

% Realign writes resliced images for all frames and a mean image.
matlabbatch{2}.spm.spatial.realign.estwrite.data{1}(1) = cfg_dep( ...
    'Slice Timing: Slice Timing Corr. Images (Sess 1)', ...
    substruct('.', 'val', '{}', {1}, '.', 'val', '{}', {1}, '.', 'val', '{}', {1}), ...
    substruct('()', {1}, '.', 'files'));
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.quality = 0.9;
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.sep = 4;
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.fwhm = 5;
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.rtm = 1;
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.interp = 2;
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.wrap = [0 0 0];
matlabbatch{2}.spm.spatial.realign.estwrite.eoptions.weight = '';
matlabbatch{2}.spm.spatial.realign.estwrite.roptions.which = [2 1];
matlabbatch{2}.spm.spatial.realign.estwrite.roptions.interp = 4;
matlabbatch{2}.spm.spatial.realign.estwrite.roptions.wrap = [0 0 0];
matlabbatch{2}.spm.spatial.realign.estwrite.roptions.mask = 1;
matlabbatch{2}.spm.spatial.realign.estwrite.roptions.prefix = 'r';

% Keep T1 fixed, move the mean functional to T1 space, and apply the same
% header transform to all realigned functional frames.
matlabbatch{3}.spm.spatial.coreg.estimate.ref = {t1_nii};

matlabbatch{3}.spm.spatial.coreg.estimate.source(1) = cfg_dep( ...
    'Realign: Estimate & Reslice: Mean Image', ...
    substruct('.', 'val', '{}', {2}, '.', 'val', '{}', {1}, '.', 'val', '{}', {1}, '.', 'val', '{}', {1}), ...
    substruct('.', 'rmean'));

matlabbatch{3}.spm.spatial.coreg.estimate.other(1) = cfg_dep( ...
    'Realign: Estimate & Reslice: Resliced Images (Sess 1)', ...
    substruct('.', 'val', '{}', {2}, '.', 'val', '{}', {1}, '.', 'val', '{}', {1}, '.', 'val', '{}', {1}), ...
    substruct('.', 'sess', '()', {1}, '.', 'rfiles'));
matlabbatch{3}.spm.spatial.coreg.estimate.eoptions.cost_fun = 'nmi';
matlabbatch{3}.spm.spatial.coreg.estimate.eoptions.sep = [4 2];
matlabbatch{3}.spm.spatial.coreg.estimate.eoptions.tol = ...
    [0.02 0.02 0.02 0.001 0.001 0.001 0.01 0.01 0.01 0.001 0.001 0.001];
matlabbatch{3}.spm.spatial.coreg.estimate.eoptions.fwhm = [7 7];

% Segment the T1 to create y_T1.nii, used as the forward deformation field.
tpm = fullfile(spm('Dir'), 'tpm', 'TPM.nii');
matlabbatch{4}.spm.spatial.preproc.channel.vols = {t1_nii};
matlabbatch{4}.spm.spatial.preproc.channel.biasreg = 0.001;
matlabbatch{4}.spm.spatial.preproc.channel.biasfwhm = 60;
matlabbatch{4}.spm.spatial.preproc.channel.write = [1 1];
for k = 1:6
    matlabbatch{4}.spm.spatial.preproc.tissue(k).tpm = {sprintf('%s,%d', tpm, k)};
end
matlabbatch{4}.spm.spatial.preproc.tissue(1).ngaus = 1;
matlabbatch{4}.spm.spatial.preproc.tissue(2).ngaus = 1;
matlabbatch{4}.spm.spatial.preproc.tissue(3).ngaus = 2;
matlabbatch{4}.spm.spatial.preproc.tissue(4).ngaus = 3;
matlabbatch{4}.spm.spatial.preproc.tissue(5).ngaus = 4;
matlabbatch{4}.spm.spatial.preproc.tissue(6).ngaus = 2;
matlabbatch{4}.spm.spatial.preproc.tissue(1).native = [1 0];
matlabbatch{4}.spm.spatial.preproc.tissue(2).native = [1 0];
matlabbatch{4}.spm.spatial.preproc.tissue(3).native = [1 0];
matlabbatch{4}.spm.spatial.preproc.tissue(4).native = [0 0];
matlabbatch{4}.spm.spatial.preproc.tissue(5).native = [0 0];
matlabbatch{4}.spm.spatial.preproc.tissue(6).native = [0 0];
for k = 1:5
    matlabbatch{4}.spm.spatial.preproc.tissue(k).warped = [0 0];
end
matlabbatch{4}.spm.spatial.preproc.tissue(6).warped = [0 0];
matlabbatch{4}.spm.spatial.preproc.warp.mrf = 1;
matlabbatch{4}.spm.spatial.preproc.warp.cleanup = 1;
matlabbatch{4}.spm.spatial.preproc.warp.reg = [0 0.001 0.5 0.05 0.2];
matlabbatch{4}.spm.spatial.preproc.warp.affreg = 'mni';
matlabbatch{4}.spm.spatial.preproc.warp.fwhm = 0;
matlabbatch{4}.spm.spatial.preproc.warp.samp = 3;
matlabbatch{4}.spm.spatial.preproc.warp.write = [1 1];
matlabbatch{4}.spm.spatial.preproc.warp.vox = NaN;
matlabbatch{4}.spm.spatial.preproc.warp.bb = [NaN NaN NaN; NaN NaN NaN];

% Normalise realigned functional frames with the T1-derived deformation.
matlabbatch{5}.spm.spatial.normalise.write.subj.def(1) = cfg_dep( ...
    'Segment: Forward Deformations', ...
    substruct('.', 'val', '{}', {4}, '.', 'val', '{}', {1}, '.', 'val', '{}', {1}), ...
    substruct('.', 'fordef', '()', {':'}));
matlabbatch{5}.spm.spatial.normalise.write.subj.resample(1) = cfg_dep( ...
    'Realign: Estimate & Reslice: Resliced Images (Sess 1)', ...
    substruct('.', 'val', '{}', {2}, '.', 'val', '{}', {1}, '.', 'val', '{}', {1}, '.', 'val', '{}', {1}), ...
    substruct('.', 'sess', '()', {1}, '.', 'rfiles'));
matlabbatch{5}.spm.spatial.normalise.write.woptions.bb = ...
    [-78 -112 -70; 78 76 85];
matlabbatch{5}.spm.spatial.normalise.write.woptions.vox = cfg.voxel_size;
matlabbatch{5}.spm.spatial.normalise.write.woptions.interp = 4;
matlabbatch{5}.spm.spatial.normalise.write.woptions.prefix = 'w';

matlabbatch{6}.spm.spatial.smooth.data(1) = cfg_dep( ...
    'Normalise: Write: Normalised Images (Subj 1)', ...
    substruct('.', 'val', '{}', {5}, '.', 'val', '{}', {1}, '.', 'val', '{}', {1}, '.', 'val', '{}', {1}), ...
    substruct('()', {1}, '.', 'files'));
matlabbatch{6}.spm.spatial.smooth.fwhm = cfg.smooth_fwhm;
matlabbatch{6}.spm.spatial.smooth.dtype = 0;
matlabbatch{6}.spm.spatial.smooth.im = 0;
matlabbatch{6}.spm.spatial.smooth.prefix = 's';

info = struct();
info.TR = json_info.TR;
info.TA = json_info.TA;
info.nslices = json_info.nslices;
info.nvols = nvols;
info.slice_order = json_info.slice_order;
info.reference_slice = json_info.reference_slice;
info.voxel_size = cfg.voxel_size;
info.smooth_fwhm = cfg.smooth_fwhm;
end
