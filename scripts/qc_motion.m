function qc = qc_motion(rp_file, nvols)
%QC_MOTION Validate SPM realignment parameters against the volume count.

if exist(rp_file, 'file') ~= 2
    error('qc_motion:MissingFile', ...
        'Motion parameter file does not exist: %s', rp_file);
end

motion = dlmread(rp_file);
[nrows, ncols] = size(motion);

if nrows ~= nvols
    error('qc_motion:WrongRowCount', ...
        '%s has %d row(s), expected %d volume(s).', ...
        rp_file, nrows, nvols);
end
if ncols ~= 6
    error('qc_motion:WrongColumnCount', ...
        '%s has %d column(s), expected 6.', rp_file, ncols);
end

qc = struct();
qc.file = rp_file;
qc.nrows = nrows;
qc.ncols = ncols;
qc.max_abs_translation_mm = max(max(abs(motion(:, 1:3))));
qc.max_abs_rotation_rad = max(max(abs(motion(:, 4:6))));
end
