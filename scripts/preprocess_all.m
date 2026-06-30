function preprocess_all(config_file)
%PREPROCESS_ALL Run SPM preprocessing across subjects and sessions.
%
% Inputs are discovered under cfg.raw_root, copied into cfg.output_root, and
% SPM is run on those derivative copies so raw NIfTI/JSON files are not
% modified by preprocessing modules that write beside their inputs.

if nargin < 1 || isempty(config_file)
    repo_root = fileparts(fileparts(mfilename('fullpath')));
    config_file = fullfile(repo_root, 'config', 'config_template.m');
end

scripts_dir = fileparts(mfilename('fullpath'));
addpath(scripts_dir);

cfg = load_preproc_config(config_file);
validate_config(cfg);

if ~exist(cfg.output_root, 'dir')
    mkdir(cfg.output_root);
end
if ~exist(cfg.log_root, 'dir')
    mkdir(cfg.log_root);
end

spm('Defaults', 'fMRI');
spm_jobman('initcfg');

subjects = resolve_subjects(cfg);
fprintf('Found %d subject(s).\n', numel(subjects));

for i_sub = 1:numel(subjects)
    subject = subjects{i_sub};
    sessions = resolve_sessions(cfg, subject);

    for i_ses = 1:numel(sessions)
        session = sessions{i_ses};
        label = session_label(session);
        fprintf('\n=== %s / %s ===\n', subject, label);

        inputs = discover_session_inputs(cfg, subject, session);
        work_dir = fullfile(cfg.output_root, subject, label, 'work');
        log_dir = fullfile(cfg.log_root, subject, label);
        ensure_dir(work_dir);
        ensure_dir(log_dir);

        run_inputs = stage_inputs(inputs, work_dir);
        func_info = read_func_json(run_inputs.func_json);
        [~, nvols] = get_nii_frames(run_inputs.func_nii);

        fprintf('Functional: %s\n', run_inputs.func_nii);
        fprintf('Anatomical: %s\n', run_inputs.t1_nii);
        fprintf('TR %.6g s, %d slices, %d volumes\n', ...
            func_info.TR, func_info.nslices, nvols);

        [matlabbatch, batch_info] = make_preproc_batch( ...
            run_inputs.func_nii, run_inputs.t1_nii, run_inputs.func_json, cfg);

        spm_jobman('run', matlabbatch);

        expected = expected_outputs(work_dir);
        check_session_outputs(expected, nvols);
        motion_qc = qc_motion(expected.rp_txt, nvols);

        log_file = fullfile(log_dir, 'preprocess_log.txt');
        write_session_log(log_file, subject, label, inputs, run_inputs, ...
            batch_info, motion_qc, expected);

        fprintf('Outputs: %s\n', work_dir);
        fprintf('Motion QC: %d rows x %d columns in %s\n', ...
            motion_qc.nrows, motion_qc.ncols, expected.rp_txt);
        fprintf('Log: %s\n', log_file);
    end
end
end

function cfg = load_preproc_config(config_file)
if isstruct(config_file)
    cfg = config_file;
    return;
end

if exist(config_file, 'file') == 2
    [config_dir, config_name] = fileparts(config_file);
    addpath(config_dir);
    cfg = feval(config_name);
else
    cfg = feval(config_file);
end
end

function validate_config(cfg)
required = {'raw_root', 'output_root', 'log_root', 'func_dir', ...
    'anat_dir', 'func_pattern', 'json_pattern', 't1_pattern', ...
    'voxel_size', 'smooth_fwhm'};
for i = 1:numel(required)
    if ~isfield(cfg, required{i}) || isempty(cfg.(required{i}))
        error('preprocess_all:ConfigMissing', ...
            'Configuration is missing cfg.%s.', required{i});
    end
end
if ~exist(cfg.raw_root, 'dir')
    error('preprocess_all:RawRootMissing', ...
        'Raw root does not exist: %s', cfg.raw_root);
end
end

function subjects = resolve_subjects(cfg)
if isfield(cfg, 'subjects') && ~isempty(cfg.subjects)
    subjects = ensure_cellstr(cfg.subjects);
    return;
end

listing = dir(fullfile(cfg.raw_root, 'sub-*'));
subjects = names_from_dirs(listing);
if isempty(subjects)
    error('preprocess_all:NoSubjects', ...
        'No subject folders found under %s. Set cfg.subjects if needed.', ...
        cfg.raw_root);
end
end

function sessions = resolve_sessions(cfg, subject)
if isfield(cfg, 'sessions') && ~isempty(cfg.sessions)
    sessions = ensure_cellstr(cfg.sessions);
    return;
end

subject_dir = fullfile(cfg.raw_root, subject);
listing = dir(fullfile(subject_dir, 'ses-*'));
sessions = names_from_dirs(listing);

if isempty(sessions)
    % Allows datasets with sub-*/func and sub-*/anat but no ses-* level.
    sessions = {''};
end
end

function inputs = discover_session_inputs(cfg, subject, session)
session_root = build_session_root(cfg.raw_root, subject, session);
subject_root = fullfile(cfg.raw_root, subject);

func_dir = fullfile(session_root, cfg.func_dir);
anat_dirs = {fullfile(session_root, cfg.anat_dir), ...
    fullfile(subject_root, cfg.anat_dir)};

func_nii = find_one_file(func_dir, cfg.func_pattern, 'functional NIfTI');
func_json = matching_json(func_nii, func_dir, cfg.json_pattern);
t1_nii = find_one_file(anat_dirs, cfg.t1_pattern, 'T1 anatomical NIfTI');

inputs = struct();
inputs.subject = subject;
inputs.session = session;
inputs.func_nii = func_nii;
inputs.func_json = func_json;
inputs.t1_nii = t1_nii;
end

function root = build_session_root(raw_root, subject, session)
if isempty(session)
    root = fullfile(raw_root, subject);
else
    root = fullfile(raw_root, subject, session);
end
end

function run_inputs = stage_inputs(inputs, work_dir)
run_inputs = struct();
run_inputs.func_nii = copy_if_missing(inputs.func_nii, ...
    fullfile(work_dir, 'func.nii'));
run_inputs.func_json = copy_if_missing(inputs.func_json, ...
    fullfile(work_dir, 'func.json'));
run_inputs.t1_nii = copy_if_missing(inputs.t1_nii, ...
    fullfile(work_dir, 'T1.nii'));
end

function dst = copy_if_missing(src, dst)
if exist(dst, 'file') == 2
    fprintf('Reusing existing staged file: %s\n', dst);
    return;
end

copyfile(src, dst);
fprintf('Staged input copy: %s\n', dst);
end

function out = expected_outputs(work_dir)
out = struct();
out.slice_timed = fullfile(work_dir, 'afunc.nii');
out.realigned = fullfile(work_dir, 'rafunc.nii');
out.normalized = fullfile(work_dir, 'wrafunc.nii');
out.smoothed = fullfile(work_dir, 'swrafunc.nii');
out.mean_func = fullfile(work_dir, 'meanafunc.nii');
out.rp_txt = fullfile(work_dir, 'rp_afunc.txt');
out.forward_deformation = fullfile(work_dir, 'y_T1.nii');
end

function check_session_outputs(expected, nvols)
fields = fieldnames(expected);
for i = 1:numel(fields)
    this_file = expected.(fields{i});
    if exist(this_file, 'file') ~= 2
        error('preprocess_all:MissingOutput', ...
            'Expected output was not created: %s', this_file);
    end
end

frame_fields = {'slice_timed', 'realigned', 'normalized', 'smoothed'};
for i = 1:numel(frame_fields)
    this_file = expected.(frame_fields{i});
    [~, out_nvols] = get_nii_frames(this_file);
    if out_nvols ~= nvols
        error('preprocess_all:FrameCountChanged', ...
            '%s has %d frame(s), expected %d.', ...
            this_file, out_nvols, nvols);
    end
end
end

function write_session_log(log_file, subject, session, inputs, run_inputs, ...
    batch_info, motion_qc, expected)
fid = fopen(log_file, 'w');
if fid < 0
    error('preprocess_all:LogOpenFailed', ...
        'Could not open log file for writing: %s', log_file);
end
cleaner = onCleanup(@() fclose(fid));

fprintf(fid, 'subject: %s\n', subject);
fprintf(fid, 'session: %s\n', session);
fprintf(fid, 'raw_func_nii: %s\n', inputs.func_nii);
fprintf(fid, 'raw_func_json: %s\n', inputs.func_json);
fprintf(fid, 'raw_t1_nii: %s\n', inputs.t1_nii);
fprintf(fid, 'staged_func_nii: %s\n', run_inputs.func_nii);
fprintf(fid, 'staged_func_json: %s\n', run_inputs.func_json);
fprintf(fid, 'staged_t1_nii: %s\n', run_inputs.t1_nii);
fprintf(fid, 'TR: %.12g\n', batch_info.TR);
fprintf(fid, 'TA: %.12g\n', batch_info.TA);
fprintf(fid, 'nslices: %d\n', batch_info.nslices);
fprintf(fid, 'nvols: %d\n', batch_info.nvols);
fprintf(fid, 'slice_order: %s\n', mat2str(batch_info.slice_order));
fprintf(fid, 'reference_slice: %d\n', batch_info.reference_slice);
fprintf(fid, 'voxel_size: %s\n', mat2str(batch_info.voxel_size));
fprintf(fid, 'smooth_fwhm: %s\n', mat2str(batch_info.smooth_fwhm));
fprintf(fid, 'motion_rows: %d\n', motion_qc.nrows);
fprintf(fid, 'motion_columns: %d\n', motion_qc.ncols);

fields = fieldnames(expected);
for i = 1:numel(fields)
    fprintf(fid, 'output_%s: %s\n', fields{i}, expected.(fields{i}));
end
end

function files = ensure_cellstr(value)
if ischar(value)
    files = {value};
elseif isstring(value)
    files = cellstr(value(:));
elseif iscell(value)
    files = value(:)';
else
    error('preprocess_all:InvalidList', ...
        'Expected a char, string, or cell array of chars.');
end
end

function names = names_from_dirs(listing)
listing = listing([listing.isdir]);
names = {listing.name};
names = names(~ismember(names, {'.', '..'}));
end

function label = session_label(session)
if isempty(session)
    label = 'single_session';
else
    label = session;
end
end

function ensure_dir(path_name)
if ~exist(path_name, 'dir')
    mkdir(path_name);
end
end

function file_name = find_one_file(search_dirs, pattern, description)
if ischar(search_dirs)
    search_dirs = {search_dirs};
end

matches = {};
for i = 1:numel(search_dirs)
    if exist(search_dirs{i}, 'dir') ~= 7
        continue;
    end
    listing = dir(fullfile(search_dirs{i}, pattern));
    listing = listing(~[listing.isdir]);
    for j = 1:numel(listing)
        matches{end + 1} = fullfile(listing(j).folder, listing(j).name); %#ok<AGROW>
    end
end

if isempty(matches)
    error('preprocess_all:InputMissing', ...
        'Could not find %s matching "%s".', description, pattern);
end
if numel(matches) > 1
    error('preprocess_all:AmbiguousInput', ...
        'Found multiple %s files matching "%s":\n%s', ...
        description, pattern, strjoin(matches, newline));
end

file_name = matches{1};
end

function json_file = matching_json(func_nii, func_dir, json_pattern)
[~, stem] = fileparts(func_nii);
candidate = fullfile(func_dir, [stem '.json']);
if exist(candidate, 'file') == 2
    json_file = candidate;
    return;
end

json_file = find_one_file(func_dir, json_pattern, 'functional JSON sidecar');
end
