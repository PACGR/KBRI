function conversions = convert_dicom_to_nifti(cfg)
%CONVERT_DICOM_TO_NIFTI Convert DICOM folders to BIDS-like NIfTI folders.
%
% This helper calls dcm2niix via MATLAB system(). It never modifies DICOM
% inputs. Converted NIfTI/JSON files are skipped unless
% cfg.overwrite_converted is true.

cfg = conversion_defaults(cfg);
validate_conversion_config(cfg);
check_dcm2niix_available(cfg.dcm2niix_path);

ensure_dir(cfg.converted_root);
ensure_dir(cfg.log_root);

subjects = resolve_subjects_for_conversion(cfg);
conversions = struct('subject', {}, 'session', {}, 'dicom_dir', {}, ...
    'output_dir', {}, 'command', {}, 'status', {}, 'output', {}, ...
    'nii_files', {}, 'json_files', {}, 'skipped', {});

for i_sub = 1:numel(subjects)
    subject = subjects{i_sub};
    sessions = resolve_sessions_for_conversion(cfg, subject);
    jobs = build_subject_conversion_jobs(cfg, subject, sessions);

    if isempty(jobs)
        error('convert_dicom_to_nifti:NoDicomFolders', ...
            'No DICOM folders found for %s under %s.', ...
            subject, fullfile(cfg.dicom_root, subject));
    end

    for i_job = 1:numel(jobs)
        job = jobs(i_job);
        ensure_dir(job.output_dir);

        log_dir = fullfile(cfg.log_root, job.subject, session_label(job.session));
        ensure_dir(log_dir);
        log_file = fullfile(log_dir, ['dcm2niix_' job.label '_log.txt']);

        before_nii = list_niftis(job.output_dir);
        before_json = list_files(job.output_dir, '*.json');
        has_existing = ~isempty(before_nii) || ~isempty(before_json);

        if has_existing && ~cfg.overwrite_converted
            status = 0;
            cmdout = sprintf(['Skipped conversion because output files already ', ...
                'exist and cfg.overwrite_converted is false.\nOutput: %s'], ...
                job.output_dir);
            cmd = build_dcm2niix_command(cfg, job);
            skipped = true;
        else
            cmd = build_dcm2niix_command(cfg, job);
            [status, cmdout] = system(cmd);
            skipped = false;
        end

        nii_files = list_niftis(job.output_dir);
        json_files = list_files(job.output_dir, '*.json');
        write_conversion_log(log_file, job, cmd, status, cmdout, ...
            nii_files, json_files, skipped);

        if status ~= 0
            error('convert_dicom_to_nifti:Dcm2niixFailed', ...
                'dcm2niix failed for %s. See log: %s', job.dicom_dir, log_file);
        end
        validate_conversion_outputs(job.output_dir, nii_files, json_files);

        conversions(end + 1) = struct( ...
            'subject', job.subject, ...
            'session', job.session, ...
            'dicom_dir', job.dicom_dir, ...
            'output_dir', job.output_dir, ...
            'command', cmd, ...
            'status', status, ...
            'output', cmdout, ...
            'nii_files', {nii_files}, ...
            'json_files', {json_files}, ...
            'skipped', skipped); %#ok<AGROW>
    end
end
end

function cfg = conversion_defaults(cfg)
if ~isfield(cfg, 'dcm2niix_compress') || isempty(cfg.dcm2niix_compress)
    cfg.dcm2niix_compress = false;
end
if ~isfield(cfg, 'overwrite_converted') || isempty(cfg.overwrite_converted)
    cfg.overwrite_converted = false;
end
if ~isfield(cfg, 'func_dir') || isempty(cfg.func_dir)
    cfg.func_dir = 'func';
end
if ~isfield(cfg, 'anat_dir') || isempty(cfg.anat_dir)
    cfg.anat_dir = 'anat';
end
if ~isfield(cfg, 'dcm2niix_filename_pattern') || isempty(cfg.dcm2niix_filename_pattern)
    cfg.dcm2niix_filename_pattern = '%f_%p_%t_%s';
end
end

function validate_conversion_config(cfg)
required = {'dicom_root', 'converted_root', 'dcm2niix_path', 'log_root'};
for i = 1:numel(required)
    if ~isfield(cfg, required{i}) || isempty(cfg.(required{i}))
        error('convert_dicom_to_nifti:ConfigMissing', ...
            'Configuration is missing cfg.%s.', required{i});
    end
end
if exist(cfg.dicom_root, 'dir') ~= 7
    error('convert_dicom_to_nifti:DicomRootMissing', ...
        'DICOM root does not exist: %s', cfg.dicom_root);
end
end

function check_dcm2niix_available(dcm2niix_path)
if contains(dcm2niix_path, filesep) || contains(dcm2niix_path, '/') || ...
        endsWith(lower(dcm2niix_path), '.exe')
    if exist(dcm2niix_path, 'file') ~= 2
        error('convert_dicom_to_nifti:Dcm2niixMissing', ...
            'dcm2niix executable does not exist: %s', dcm2niix_path);
    end
end

[status, output] = system(sprintf('%s -h', quote_arg(dcm2niix_path)));
if status ~= 0 && isempty(strfind(lower(output), 'dcm2niix')) %#ok<STREMP>
    error('convert_dicom_to_nifti:Dcm2niixMissing', ...
        'Could not run dcm2niix at "%s". Output:\n%s', dcm2niix_path, output);
end
end

function subjects = resolve_subjects_for_conversion(cfg)
if isfield(cfg, 'subjects') && ~isempty(cfg.subjects)
    subjects = ensure_cellstr(cfg.subjects);
    return;
end

listing = dir(fullfile(cfg.dicom_root, 'sub-*'));
subjects = names_from_dirs(listing);
if isempty(subjects)
    error('convert_dicom_to_nifti:NoSubjects', ...
        'No subject folders found under %s. Set cfg.subjects if needed.', ...
        cfg.dicom_root);
end
end

function sessions = resolve_sessions_for_conversion(cfg, subject)
if isfield(cfg, 'sessions') && ~isempty(cfg.sessions)
    sessions = ensure_cellstr(cfg.sessions);
    return;
end

subject_dir = fullfile(cfg.dicom_root, subject);
listing = dir(fullfile(subject_dir, 'ses-*'));
sessions = names_from_dirs(listing);
if isempty(sessions)
    sessions = {''};
end
end

function jobs = build_subject_conversion_jobs(cfg, subject, sessions)
jobs = struct('subject', {}, 'session', {}, 'label', {}, ...
    'dicom_dir', {}, 'output_dir', {});
seen = {};

subject_dicom_root = fullfile(cfg.dicom_root, subject);
subject_output_root = fullfile(cfg.converted_root, subject);
subject_anat = fullfile(subject_dicom_root, cfg.anat_dir);
if exist(subject_anat, 'dir') == 7
    [jobs, seen] = add_job(jobs, seen, cfg, subject, '', cfg.anat_dir, ...
        subject_anat, fullfile(subject_output_root, cfg.anat_dir));
end

for i_ses = 1:numel(sessions)
    session = sessions{i_ses};
    session_dicom_root = build_session_root(cfg.dicom_root, subject, session);
    session_output_root = build_session_root(cfg.converted_root, subject, session);

    func_dicom = fullfile(session_dicom_root, cfg.func_dir);
    anat_dicom = fullfile(session_dicom_root, cfg.anat_dir);
    added_modality = false;

    if exist(func_dicom, 'dir') == 7
        [jobs, seen] = add_job(jobs, seen, cfg, subject, session, cfg.func_dir, ...
            func_dicom, fullfile(session_output_root, cfg.func_dir));
        added_modality = true;
    end
    if exist(anat_dicom, 'dir') == 7
        [jobs, seen] = add_job(jobs, seen, cfg, subject, session, cfg.anat_dir, ...
            anat_dicom, fullfile(session_output_root, cfg.anat_dir));
        added_modality = true;
    end

    if ~added_modality && exist(session_dicom_root, 'dir') == 7
        [jobs, seen] = add_job(jobs, seen, cfg, subject, session, 'session', ...
            session_dicom_root, session_output_root);
    end
end
end

function [jobs, seen] = add_job(jobs, seen, cfg, subject, session, label, ...
    dicom_dir, output_dir) %#ok<INUSD>
key = [dicom_dir '|' output_dir];
if any(strcmp(seen, key))
    return;
end

seen{end + 1} = key;
jobs(end + 1) = struct( ... %#ok<AGROW>
    'subject', subject, ...
    'session', session, ...
    'label', sanitize_label(label), ...
    'dicom_dir', dicom_dir, ...
    'output_dir', output_dir);
end

function cmd = build_dcm2niix_command(cfg, job)
if cfg.dcm2niix_compress
    compress_opt = 'y';
else
    compress_opt = 'n';
end

cmd = sprintf('%s -b y -z %s -f %s -o %s %s', ...
    quote_arg(cfg.dcm2niix_path), ...
    compress_opt, ...
    quote_arg(cfg.dcm2niix_filename_pattern), ...
    quote_arg(job.output_dir), ...
    quote_arg(job.dicom_dir));
end

function validate_conversion_outputs(output_dir, nii_files, json_files)
if isempty(nii_files)
    error('convert_dicom_to_nifti:NoNiftiOutput', ...
        'Conversion did not produce any NIfTI files in %s.', output_dir);
end
if isempty(json_files)
    error('convert_dicom_to_nifti:NoJsonOutput', ...
        'Conversion did not produce any JSON sidecars in %s.', output_dir);
end
end

function write_conversion_log(log_file, job, cmd, status, cmdout, ...
    nii_files, json_files, skipped)
fid = fopen(log_file, 'w');
if fid < 0
    error('convert_dicom_to_nifti:LogOpenFailed', ...
        'Could not open conversion log for writing: %s', log_file);
end
cleaner = onCleanup(@() fclose(fid));

fprintf(fid, 'subject: %s\n', job.subject);
fprintf(fid, 'session: %s\n', session_label(job.session));
fprintf(fid, 'dicom_dir: %s\n', job.dicom_dir);
fprintf(fid, 'output_dir: %s\n', job.output_dir);
fprintf(fid, 'skipped_existing_outputs: %d\n', skipped);
fprintf(fid, 'command: %s\n', cmd);
fprintf(fid, 'status: %d\n', status);
fprintf(fid, 'nifti_outputs: %s\n', strjoin(nii_files, '; '));
fprintf(fid, 'json_outputs: %s\n', strjoin(json_files, '; '));
fprintf(fid, 'dcm2niix_output:\n%s\n', cmdout);
end

function files = list_niftis(folder_name)
files = [list_files(folder_name, '*.nii'), list_files(folder_name, '*.nii.gz')];
end

function files = list_files(folder_name, pattern)
if exist(folder_name, 'dir') ~= 7
    files = {};
    return;
end

listing = dir(fullfile(folder_name, pattern));
listing = listing(~[listing.isdir]);
files = cell(1, numel(listing));
for i = 1:numel(listing)
    files{i} = fullfile(listing(i).folder, listing(i).name);
end
end

function root = build_session_root(base_root, subject, session)
if isempty(session)
    root = fullfile(base_root, subject);
else
    root = fullfile(base_root, subject, session);
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
    error('convert_dicom_to_nifti:InvalidList', ...
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

function label = sanitize_label(label)
label = regexprep(label, '[^A-Za-z0-9_-]', '_');
end

function ensure_dir(path_name)
if ~exist(path_name, 'dir')
    mkdir(path_name);
end
end

function quoted = quote_arg(value)
value = char(value);
quoted = ['"' strrep(value, '"', '\"') '"'];
end
