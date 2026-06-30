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
cfg = apply_preproc_defaults(cfg);

if cfg.run_dicom_conversion
    fprintf('Running DICOM-to-NIfTI conversion from %s\n', cfg.dicom_root);
    conversions = convert_dicom_to_nifti(cfg);
    fprintf('Completed %d conversion job(s). Preprocessing will read from %s\n', ...
        numel(conversions), cfg.converted_root);
    cfg.raw_root = cfg.converted_root;
end

validate_config(cfg);

if ~exist(cfg.output_root, 'dir')
    mkdir(cfg.output_root);
end
if ~exist(cfg.log_root, 'dir')
    mkdir(cfg.log_root);
end

spm('Defaults', 'fMRI');
spm_jobman('initcfg');

subjects = resolve_subjects(cfg, cfg.raw_root);
fprintf('Found %d subject(s).\n', numel(subjects));

for i_sub = 1:numel(subjects)
    subject = subjects{i_sub};
    if strcmpi(cfg.layout, 'subject_run_folders')
        runs = discover_subject_runs(cfg, subject);
        for i_run = 1:numel(runs)
            inputs = runs(i_run);
            run_label = inputs.run;
            fprintf('\n=== %s / %s ===\n', subject, run_label);

            func_work_dir = fullfile(cfg.output_root, subject, ...
                cfg.func_dir, run_label);
            anat_work_dir = fullfile(cfg.output_root, subject, cfg.anat_dir);
            log_dir = fullfile(cfg.log_root, subject, run_label);

            process_one_run(cfg, subject, '', run_label, inputs, ...
                func_work_dir, anat_work_dir, log_dir);
        end
    else
        sessions = resolve_sessions(cfg, subject);

        for i_ses = 1:numel(sessions)
            session = sessions{i_ses};
            label = session_label(session);
            fprintf('\n=== %s / %s ===\n', subject, label);

            inputs = discover_session_inputs(cfg, subject, session);
            work_dir = fullfile(cfg.output_root, subject, label, 'work');
            log_dir = fullfile(cfg.log_root, subject, label);

            process_one_run(cfg, subject, session, label, inputs, ...
                work_dir, work_dir, log_dir);
        end
    end
end
end

function process_one_run(cfg, subject, session, run_label, inputs, ...
    func_work_dir, anat_work_dir, log_dir)
ensure_dir(func_work_dir);
ensure_dir(anat_work_dir);
ensure_dir(log_dir);

run_inputs = stage_inputs(inputs, func_work_dir, anat_work_dir);
% Validate dcm2niix timing metadata before SPM batch construction.
func_info = read_func_json(run_inputs.func_json);
[~, nvols] = get_nii_frames(run_inputs.func_nii);

fprintf('Subject: %s\n', subject);
fprintf('Run: %s\n', run_label);
fprintf('Functional: %s\n', run_inputs.func_nii);
fprintf('Anatomical: %s\n', run_inputs.t1_nii);
fprintf('TR %.6g s, %d slices, %d volumes\n', ...
    func_info.TR, func_info.nslices, nvols);
fprintf('Output folder: %s\n', func_work_dir);

[matlabbatch, batch_info] = make_preproc_batch( ...
    run_inputs.func_nii, run_inputs.t1_nii, run_inputs.func_json, cfg);

spm_jobman('run', matlabbatch);

expected = expected_outputs(func_work_dir, anat_work_dir);
check_session_outputs(expected, nvols);
motion_qc = qc_motion(expected.rp_txt, nvols);

log_file = fullfile(log_dir, 'preprocess_log.txt');
write_session_log(log_file, subject, session, run_label, inputs, run_inputs, ...
    batch_info, motion_qc, expected, func_work_dir, anat_work_dir);

fprintf('Outputs: %s\n', func_work_dir);
fprintf('Motion QC: %d rows x %d columns in %s\n', ...
    motion_qc.nrows, motion_qc.ncols, expected.rp_txt);
fprintf('Log: %s\n', log_file);
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

function cfg = apply_preproc_defaults(cfg)
if ~isfield(cfg, 'run_dicom_conversion') || isempty(cfg.run_dicom_conversion)
    cfg.run_dicom_conversion = false;
end
if ~isfield(cfg, 'dcm2niix_compress') || isempty(cfg.dcm2niix_compress)
    cfg.dcm2niix_compress = false;
end
if ~isfield(cfg, 'overwrite_converted') || isempty(cfg.overwrite_converted)
    cfg.overwrite_converted = false;
end
if ~isfield(cfg, 'dcm2niix_filename_pattern') || isempty(cfg.dcm2niix_filename_pattern)
    cfg.dcm2niix_filename_pattern = '%f_%p_%t_%s';
end
if (~isfield(cfg, 'converted_root') || isempty(cfg.converted_root)) && ...
        isfield(cfg, 'raw_root')
    cfg.converted_root = cfg.raw_root;
end
if ~isfield(cfg, 'layout') || isempty(cfg.layout)
    cfg.layout = 'bids';
end
if ~isfield(cfg, 'subject_pattern') || isempty(cfg.subject_pattern)
    cfg.subject_pattern = '*';
end
if ~isfield(cfg, 'subjects') || isempty(cfg.subjects)
    cfg.subjects = {};
end
if ~isfield(cfg, 'exclude_subject_dirs') || isempty(cfg.exclude_subject_dirs)
    cfg.exclude_subject_dirs = {'converted', 'derivatives', 'logs', '.', '..'};
end
if ~isfield(cfg, 'run_dir_patterns') || isempty(cfg.run_dir_patterns)
    cfg.run_dir_patterns = {'face_run*'};
end
if ~isfield(cfg, 't1_dir_pattern') || isempty(cfg.t1_dir_pattern)
    cfg.t1_dir_pattern = 't1';
end
end

function validate_config(cfg)
required = {'raw_root', 'output_root', 'log_root', 'layout', ...
    'func_dir', 'anat_dir', 'func_pattern', 'json_pattern', ...
    't1_pattern', 'voxel_size', 'smooth_fwhm'};
for i = 1:numel(required)
    if ~isfield(cfg, required{i}) || isempty(cfg.(required{i}))
        error('preprocess_all:ConfigMissing', ...
            'Configuration is missing cfg.%s.', required{i});
    end
end
if strcmpi(cfg.layout, 'subject_run_folders')
    required_layout = {'run_dir_patterns', 't1_dir_pattern'};
    for i = 1:numel(required_layout)
        if ~isfield(cfg, required_layout{i}) || isempty(cfg.(required_layout{i}))
            error('preprocess_all:ConfigMissing', ...
                'Configuration is missing cfg.%s.', required_layout{i});
        end
    end
elseif ~strcmpi(cfg.layout, 'bids')
    error('preprocess_all:UnsupportedLayout', ...
        'Unsupported cfg.layout "%s". Use "subject_run_folders" or "bids".', ...
        cfg.layout);
end
if ~exist(cfg.raw_root, 'dir')
    error('preprocess_all:RawRootMissing', ...
        'Raw root does not exist: %s', cfg.raw_root);
end
end

function subjects = resolve_subjects(cfg, root_dir)
if isfield(cfg, 'subjects') && ~isempty(cfg.subjects)
    subjects = ensure_cellstr(cfg.subjects);
    return;
end

listing = dir(fullfile(root_dir, cfg.subject_pattern));
subjects = names_from_dirs(listing);
subjects = subjects(~ismember(subjects, ensure_cellstr(cfg.exclude_subject_dirs)));
if isempty(subjects)
    error('preprocess_all:NoSubjects', ...
        'No subject folders found under %s matching "%s". Set cfg.subjects if needed.', ...
        root_dir, cfg.subject_pattern);
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
inputs.run = session_label(session);
inputs.func_nii = func_nii;
inputs.func_json = func_json;
inputs.t1_nii = t1_nii;
end

function runs = discover_subject_runs(cfg, subject)
subject_root = fullfile(cfg.raw_root, subject);
func_parent = fullfile(subject_root, cfg.func_dir);
if exist(func_parent, 'dir') ~= 7
    func_parent = subject_root;
end

anat_dir = fullfile(subject_root, cfg.anat_dir);
if exist(anat_dir, 'dir') == 7
    t1_dirs = {anat_dir};
else
    t1_dirs = find_matching_dirs(subject_root, cfg.t1_dir_pattern, ...
        'T1 anatomical folders');
end
if isempty(t1_dirs)
    error('preprocess_all:NoT1Folder', ...
        'No T1 folder found for %s under %s. Checked "%s" and "%s".', ...
        subject, subject_root, cfg.anat_dir, ...
        pattern_description(ensure_cellstr(cfg.t1_dir_pattern)));
end
if numel(t1_dirs) > 1
    error('preprocess_all:AmbiguousT1Folder', ...
        'Found multiple T1 folders for %s:\n%s', ...
        subject, strjoin(t1_dirs, newline));
end

run_dirs = find_matching_dirs(func_parent, cfg.run_dir_patterns, ...
    'functional run folders');
run_dirs = run_dirs(~ismember(run_dirs, t1_dirs));
if isempty(run_dirs)
    error('preprocess_all:NoRuns', ...
        'No functional run folders found for %s under %s matching "%s".', ...
        subject, func_parent, pattern_description(ensure_cellstr(cfg.run_dir_patterns)));
end

t1_nii = find_one_file(t1_dirs{1}, cfg.t1_pattern, 'T1 anatomical NIfTI');
run_template = struct('subject', '', 'session', '', 'run', '', ...
    'func_nii', '', 'func_json', '', 't1_nii', '');
runs = repmat(run_template, 1, numel(run_dirs));

for i = 1:numel(run_dirs)
    run_dir = run_dirs{i};
    [~, run_label] = fileparts(run_dir);
    func_nii = find_one_file(run_dir, cfg.func_pattern, ...
        sprintf('functional NIfTI for run %s', run_label));
    func_json = matching_json(func_nii, run_dir, cfg.json_pattern);
    runs(i) = struct( ...
        'subject', subject, ...
        'session', '', ...
        'run', sanitize_label(run_label), ...
        'func_nii', func_nii, ...
        'func_json', func_json, ...
        't1_nii', t1_nii);
end
end

function root = build_session_root(raw_root, subject, session)
if isempty(session)
    root = fullfile(raw_root, subject);
else
    root = fullfile(raw_root, subject, session);
end
end

function run_inputs = stage_inputs(inputs, func_work_dir, anat_work_dir)
run_inputs = struct();
run_inputs.func_nii = copy_if_missing(inputs.func_nii, ...
    fullfile(func_work_dir, 'func.nii'));
run_inputs.func_json = copy_if_missing(inputs.func_json, ...
    fullfile(func_work_dir, 'func.json'));
run_inputs.t1_nii = copy_if_missing(inputs.t1_nii, ...
    fullfile(anat_work_dir, 'T1.nii'));
end

function dst = copy_if_missing(src, dst)
if exist(dst, 'file') == 2
    fprintf('Reusing existing staged file: %s\n', dst);
    return;
end

copyfile(src, dst);
fprintf('Staged input copy: %s\n', dst);
end

function out = expected_outputs(func_work_dir, anat_work_dir)
out = struct();
out.slice_timed = fullfile(func_work_dir, 'afunc.nii');
out.realigned = fullfile(func_work_dir, 'rafunc.nii');
out.normalized = fullfile(func_work_dir, 'wrafunc.nii');
out.smoothed = fullfile(func_work_dir, 'swrafunc.nii');
out.mean_func = fullfile(func_work_dir, 'meanafunc.nii');
out.rp_txt = fullfile(func_work_dir, 'rp_afunc.txt');
out.gray_matter = fullfile(anat_work_dir, 'c1T1.nii');
out.white_matter = fullfile(anat_work_dir, 'c2T1.nii');
out.csf = fullfile(anat_work_dir, 'c3T1.nii');
out.bias_corrected_t1 = fullfile(anat_work_dir, 'mT1.nii');
out.forward_deformation = fullfile(anat_work_dir, 'y_T1.nii');
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

function write_session_log(log_file, subject, session, run_label, inputs, ...
    run_inputs, batch_info, motion_qc, expected, func_work_dir, anat_work_dir)
fid = fopen(log_file, 'w');
if fid < 0
    error('preprocess_all:LogOpenFailed', ...
        'Could not open log file for writing: %s', log_file);
end
cleaner = onCleanup(@() fclose(fid));

fprintf(fid, 'subject: %s\n', subject);
fprintf(fid, 'session: %s\n', session);
fprintf(fid, 'run: %s\n', run_label);
fprintf(fid, 'raw_func_nii: %s\n', inputs.func_nii);
fprintf(fid, 'raw_func_json: %s\n', inputs.func_json);
fprintf(fid, 'raw_t1_nii: %s\n', inputs.t1_nii);
fprintf(fid, 'staged_func_nii: %s\n', run_inputs.func_nii);
fprintf(fid, 'staged_func_json: %s\n', run_inputs.func_json);
fprintf(fid, 'staged_t1_nii: %s\n', run_inputs.t1_nii);
fprintf(fid, 'func_output_dir: %s\n', func_work_dir);
fprintf(fid, 'anat_output_dir: %s\n', anat_work_dir);
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

function dirs = find_matching_dirs(parent_dir, patterns, description)
patterns = ensure_cellstr(patterns);
dirs = {};
if exist(parent_dir, 'dir') ~= 7
    return;
end

for i_pattern = 1:numel(patterns)
    listing = dir(fullfile(parent_dir, patterns{i_pattern}));
    listing = listing([listing.isdir]);
    for i = 1:numel(listing)
        if ismember(listing(i).name, {'.', '..'})
            continue;
        end
        this_dir = fullfile(listing(i).folder, listing(i).name);
        if ~any(strcmp(dirs, this_dir))
            dirs{end + 1} = this_dir; %#ok<AGROW>
        end
    end
end

if isempty(dirs)
    return;
end

[~, order] = sort(lower(dirs));
dirs = dirs(order);
if nargin >= 3
    fprintf('Found %d %s under %s.\n', numel(dirs), description, parent_dir);
end
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
patterns = ensure_cellstr(pattern);

matches = {};
for i = 1:numel(search_dirs)
    if exist(search_dirs{i}, 'dir') ~= 7
        continue;
    end
    for i_pattern = 1:numel(patterns)
        listing = dir(fullfile(search_dirs{i}, patterns{i_pattern}));
        listing = listing(~[listing.isdir]);
        for j = 1:numel(listing)
            this_match = fullfile(listing(j).folder, listing(j).name);
            if ~any(strcmp(matches, this_match))
                matches{end + 1} = this_match; %#ok<AGROW>
            end
        end
    end
end

if isempty(matches)
    error('preprocess_all:InputMissing', ...
        'Could not find %s matching "%s".', ...
        description, pattern_description(patterns));
end
if numel(matches) > 1
    error('preprocess_all:AmbiguousInput', ...
        'Found multiple %s files matching "%s":\n%s', ...
        description, pattern_description(patterns), strjoin(matches, newline));
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

function text = pattern_description(patterns)
text = strjoin(patterns, ', ');
end

function label = sanitize_label(label)
label = regexprep(label, '[^A-Za-z0-9_-]', '_');
end
