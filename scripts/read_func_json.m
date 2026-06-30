function info = read_func_json(json_file)
%READ_FUNC_JSON Parse dcm2niix JSON timing fields for SPM preprocessing.

if exist(json_file, 'file') ~= 2
    error('read_func_json:MissingFile', ...
        'Functional JSON sidecar does not exist: %s', json_file);
end

raw = jsondecode(fileread(json_file));

if ~isfield(raw, 'RepetitionTime') || isempty(raw.RepetitionTime)
    error('read_func_json:MissingRepetitionTime', ...
        'JSON is missing required field RepetitionTime: %s', json_file);
end
if ~isfield(raw, 'SliceTiming') || isempty(raw.SliceTiming)
    error('read_func_json:MissingSliceTiming', ...
        'JSON is missing required field SliceTiming: %s', json_file);
end

slice_timing = double(raw.SliceTiming(:)');
if any(~isfinite(slice_timing))
    error('read_func_json:InvalidSliceTiming', ...
        'SliceTiming contains non-finite values: %s', json_file);
end

TR = double(raw.RepetitionTime);
if ~isscalar(TR) || ~isfinite(TR) || TR <= 0
    error('read_func_json:InvalidRepetitionTime', ...
        'RepetitionTime must be a positive scalar in seconds: %s', json_file);
end

nslices = numel(slice_timing);
[~, slice_order] = sort(slice_timing, 'ascend');
middle_time = (min(slice_timing) + max(slice_timing)) / 2;
[~, reference_slice] = min(abs(slice_timing - middle_time));

info = struct();
info.TR = TR;
info.slice_timing = slice_timing;
info.nslices = nslices;
info.slice_order = slice_order;
info.reference_slice = reference_slice;
info.TA = TR - (TR / nslices);
end
