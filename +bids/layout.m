function BIDS = layout(root,tolerant)
    % Parse a directory structure formated according to the BIDS standard
    % FORMAT BIDS = bids.layout(root)
    % root     - directory formated according to BIDS [Default: pwd]
    % tolerant - if set to 0 (default) only files g
    % BIDS     - structure containing the BIDS file layout
    %__________________________________________________________________________
    %
    % BIDS (Brain Imaging Data Structure): https://bids.neuroimaging.io/
    %   The brain imaging data structure, a format for organizing and
    %   describing outputs of neuroimaging experiments.
    %   K. J. Gorgolewski et al, Scientific Data, 2016.
    %__________________________________________________________________________
    
    % Copyright (C) 2016-2018, Guillaume Flandin, Wellcome Centre for Human Neuroimaging
    % Copyright (C) 2018--, BIDS-MATLAB developers
    
    
    
    %-Validate input arguments
    %==========================================================================
    if ~nargin
        root = pwd;
    elseif nargin == 1
        if ischar(root)
            root = bids.internal.file_utils(root, 'CPath');
        elseif isstruct(root)
            BIDS = root; % or BIDS = bids.layout(root.root);
            return;
        else
            error('Invalid syntax.');
        end
    elseif nargin > 2
        error('Too many input arguments.');
    end
    
    if ~exist('tolerant','var')
        tolerant = false;
    end
    
    %-BIDS structure
    %==========================================================================
    
    BIDS = struct(...
        'dir',root, ...               % BIDS directory
        'description',struct([]), ... % content of dataset_description.json
        'sessions',{{}},...           % cellstr of sessions
        'scans',struct([]),...        % content of sub-<participant_label>_scans.tsv (should go within subjects)
        'sess',struct([]),...         % content of sub-participants_label>_sessions.tsv (should go within subjects)
        'participants',struct([]),... % content of participants.tsv
        'subjects',struct([]));       % structure array of subjects
    
    
    % -Validation of BIDS root directory
    % ==========================================================================
    if ~exist(BIDS.dir, 'dir')
        error('BIDS directory does not exist: ''%s''', BIDS.dir);
        
    elseif ~exist(fullfile(BIDS.dir, 'dataset_description.json'), 'file')
        
        msg = sprintf('BIDS directory not valid: missing dataset_description.json: ''%s''', ...
            BIDS.dir);
        
        tolerant_message(tolerant, msg);
        
    end
    
    % -Dataset description
    % ==========================================================================
    try
        BIDS.description = bids.util.jsondecode(fullfile(BIDS.dir, 'dataset_description.json'));
    catch err
        msg = sprintf('BIDS dataset description could not be read: %s', err.message);
        tolerant_message(tolerant, msg);
    end
    
    fields_to_check = {'BIDSVersion', 'Name'};
    for iField = 1:numel(fields_to_check)
        
        if ~isfield(BIDS.description, fields_to_check{iField})
            msg = sprintf(...
                'BIDS dataset description not valid: missing %s field.', ...
                fields_to_check{iField});
            tolerant_message(tolerant, msg);
        end
        
    end
    
    % -Optional directories
    % ==========================================================================
    % [code/]
    % [derivatives/]
    % [stimuli/]
    % [sourcedata/]
    % [phenotype/]
    
    % -Scans key file
    % ==========================================================================
    
    % sub-<participant_label>/[ses-<session_label>/]
    %     sub-<participant_label>_scans.tsv
    
    % See also optional README and CHANGES files
    
    %-Participant key file
    %==========================================================================
    p = bids.internal.file_utils('FPList',BIDS.dir,'^participants\.tsv$');
    if ~isempty(p)
        try
            BIDS.participants = bids.util.tsvread(p);
        catch
            msg = ['unable to read ' p];
            tolerant_message(tolerant, msg);
        end
    end
    p = bids.internal.file_utils('FPList',BIDS.dir,'^participants\.json$');
    if ~isempty(p)
        BIDS.participants.meta = bids.util.jsondecode(p);
    end
    
    % -Sessions file
    % ==========================================================================
    
    % sub-<participant_label>/[ses-<session_label>/]
    %      sub-<participant_label>[_ses-<session_label>]_sessions.tsv
    
    % -Tasks: JSON files are accessed through metadata
    % ==========================================================================
    % t = bids.internal.file_utils('FPList',BIDS.dir,...
    %    '^task-.*_(beh|bold|events|channels|physio|stim|meg)\.(json|tsv)$');
    
    % -Subjects
    % ==========================================================================
    sub = cellstr(bids.internal.file_utils('List', BIDS.dir, 'dir', '^sub-.*$'));
    if isequal(sub, {''})
        error('No subjects found in BIDS directory.');
    end
    
    for iSub = 1:numel(sub)
        sess = cellstr(bids.internal.file_utils('List', fullfile(BIDS.dir, sub{iSub}), 'dir', '^ses-.*$'));
        for iSess = 1:numel(sess)
            if isempty(BIDS.subjects)
                BIDS.subjects = parse_subject(BIDS.dir, sub{iSub}, sess{iSess});
            else
                BIDS.subjects(end + 1) = parse_subject(BIDS.dir, sub{iSub}, sess{iSess});
            end
        end
    end
    
end

function tolerant_message(tolerant, msg)
    if tolerant
        warning(msg);
    else
        error(msg);
    end
end

% ==========================================================================
% -Parse a subject's directory
% ==========================================================================
function subject = parse_subject(pth, subjname, sesname)
    % For each modality (anat, func, eeg...) all the files from the
    % corresponding directory are listed and their filenames parsed with extra
    % BIDS valid entities listed (e.g. 'acq','ce','rec','fa'...).
    
    subject.name    = subjname;   % subject name ('sub-<participant_label>')
    subject.path    = fullfile(pth, subjname, sesname); % full path to subject directory
    subject.session = sesname; % session name ('' or 'ses-<label>')
    subject.anat    = struct([]); % anatomy imaging data
    subject.func    = struct([]); % task imaging data
    subject.fmap    = struct([]); % fieldmap data
    subject.beh     = struct([]); % behavioral experiment data
    subject.dwi     = struct([]); % diffusion imaging data
    subject.eeg     = struct([]); % EEG data
    subject.meg     = struct([]); % MEG data
    subject.ieeg    = struct([]); % iEEG data
    subject.pet     = struct([]); % PET imaging data
    
    subject = parse_anat(subject);
    subject = parse_func(subject);
    subject = parse_fmap(subject);
    subject = parse_eeg(subject);
    subject = parse_meg(subject);
    subject = parse_beh(subject);
    subject = parse_dwi(subject);
    subject = parse_pet(subject);
    subject = parse_ieeg(subject);
    
end

function f = convert_to_cell(f)
    if isempty(f)
        f = {};
    else
        f = cellstr(f);
    end
end

function subject = parse_anat(subject)
    
    % --------------------------------------------------------------------------
    % -Anatomy imaging data
    % --------------------------------------------------------------------------
    pth = fullfile(subject.path, 'anat');
    if exist(pth, 'dir')
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s.*_([a-zA-Z0-9]+){1}\\.nii(\\.gz)?$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            % -Anatomy imaging data file
            % ------------------------------------------------------------------
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'acq', 'ce', 'rec', 'fa', 'echo', 'inv', 'run'});
            subject.anat = [subject.anat p];
            
        end
    end
    
end

function subject = parse_func(subject)
    
    % --------------------------------------------------------------------------
    % -Task imaging data
    % --------------------------------------------------------------------------
    pth = fullfile(subject.path, 'func');
    if exist(pth, 'dir')
        
        % -Task imaging data file
        % ----------------------------------------------------------------------
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s.*_task-.*_bold\\.nii(\\.gz)?$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task', 'acq', 'rec', 'fa', 'echo', 'inv', 'run', 'recording', 'meta'});
            subject.func = [subject.func p];
            subject.func(end).meta = struct([]); % ?
            
        end
        
        % -Task events file
        % ----------------------------------------------------------------------
        % (!) TODO: events file can also be stored at higher levels (inheritance principle)
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s.*_task-.*_events\\.tsv$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task', 'acq', 'rec', 'fa', 'echo', 'inv', 'run', 'recording', 'meta'});
            subject.func = [subject.func p];
            subject.func(end).meta = bids.util.tsvread(fullfile(pth, fileList{i})); % ?
            
        end
        
        % -Physiological and other continuous recordings file
        % ----------------------------------------------------------------------
        % (!) TODO: stim file can also be stored at higher levels (inheritance principle)
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s.*_task-.*_(physio|stim)\\.tsv\\.gz$', subject.name));
        % see also [_recording-<label>]
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task', 'acq', 'rec', 'fa', 'echo', 'inv', 'run', 'recording', 'meta'});
            subject.func = [subject.func p];
            subject.func(end).meta = struct([]); % ?
            
        end
    end
end

function subject = parse_fmap(subject)
    
    % --------------------------------------------------------------------------
    % -Fieldmap data
    % --------------------------------------------------------------------------
    pth = fullfile(subject.path, 'fmap');
    if exist(pth, 'dir')
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s.*\\.nii(\\.gz)?$', subject.name));
        fileList = convert_to_cell(fileList);
        j = 1;
        
        % -Phase difference image and at least one magnitude image
        % ----------------------------------------------------------------------
        labels = regexp(fileList, [ ...
            '^sub-[a-zA-Z0-9]+' ...              % sub-<participant_label>
            '(?<ses>_ses-[a-zA-Z0-9]+)?' ...     % ses-<label>
            '(?<acq>_acq-[a-zA-Z0-9]+)?' ...     % acq-<label>
            '(?<run>_run-[a-zA-Z0-9]+)?' ...     % run-<index>
            '_phasediff\.nii(\.gz)?$'], 'names'); % NIfTI file extension
        if any(~cellfun(@isempty, labels))
            idx = find(~cellfun(@isempty, labels));
            for i = 1:numel(idx)
                fb = bids.internal.file_utils(bids.internal.file_utils(fileList{idx(i)}, 'basename'), 'basename');
                metafile = fullfile(pth, bids.internal.file_utils(fb, 'ext', 'json'));
                subject.fmap(j).type = 'phasediff';
                subject.fmap(j).filename = fileList{idx(i)};
                subject.fmap(j).magnitude = { ...
                    strrep(fileList{idx(i)}, '_phasediff.nii', '_magnitude1.nii'), ...
                    strrep(fileList{idx(i)}, '_phasediff.nii', '_magnitude2.nii')}; % optional
                subject.fmap(j).ses = regexprep(labels{idx(i)}.ses, '^_[a-zA-Z0-9]+-', '');
                subject.fmap(j).acq = regexprep(labels{idx(i)}.acq, '^_[a-zA-Z0-9]+-', '');
                subject.fmap(j).run = regexprep(labels{idx(i)}.run, '^_[a-zA-Z0-9]+-', '');
                if exist(metafile, 'file')
                    subject.fmap(j).meta = bids.util.jsondecode(metafile);
                else
                    % (!) TODO: file can also be stored at higher levels (inheritance principle)
                    subject.fmap(j).meta = struct([]); % ?
                end
                j = j + 1;
            end
        end
        
        % -Two phase images and two magnitude images
        % ----------------------------------------------------------------------
        labels = regexp(fileList, [ ...
            '^sub-[a-zA-Z0-9]+' ...           % sub-<participant_label>
            '(?<ses>_ses-[a-zA-Z0-9]+)?' ...  % ses-<label>
            '(?<acq>_acq-[a-zA-Z0-9]+)?' ...  % acq-<label>
            '(?<run>_run-[a-zA-Z0-9]+)?' ...  % run-<index>
            '_phase1\.nii(\.gz)?$'], 'names'); % NIfTI file extension
        if any(~cellfun(@isempty, labels))
            idx = find(~cellfun(@isempty, labels));
            for i = 1:numel(idx)
                fb = bids.internal.file_utils(bids.internal.file_utils(fileList{idx(i)}, 'basename'), 'basename');
                metafile = fullfile(pth, bids.internal.file_utils(fb, 'ext', 'json'));
                subject.fmap(j).type = 'phase12';
                subject.fmap(j).filename = { ...
                    fileList{idx(i)}, ...
                    strrep(fileList{idx(i)}, '_phase1.nii', '_phase2.nii')};
                subject.fmap(j).magnitude = { ...
                    strrep(fileList{idx(i)}, '_phase1.nii', '_magnitude1.nii'), ...
                    strrep(fileList{idx(i)}, '_phase1.nii', '_magnitude2.nii')};
                subject.fmap(j).ses = regexprep(labels{idx(i)}.ses, '^_[a-zA-Z0-9]+-', '');
                subject.fmap(j).acq = regexprep(labels{idx(i)}.acq, '^_[a-zA-Z0-9]+-', '');
                subject.fmap(j).run = regexprep(labels{idx(i)}.run, '^_[a-zA-Z0-9]+-', '');
                if exist(metafile, 'file')
                    subject.fmap(j).meta = { ...
                        bids.util.jsondecode(metafile), ...
                        bids.util.jsondecode(strrep(metafile, '_phase1.json', '_phase2.json'))};
                else
                    % (!) TODO: file can also be stored at higher levels (inheritance principle)
                    subject.fmap(j).meta = struct([]); % ?
                end
                j = j + 1;
            end
        end
        
        % -A single, real fieldmap image
        % ----------------------------------------------------------------------
        labels = regexp(fileList, [ ...
            '^sub-[a-zA-Z0-9]+' ...             % sub-<participant_label>
            '(?<ses>_ses-[a-zA-Z0-9]+)?' ...    % ses-<label>
            '(?<acq>_acq-[a-zA-Z0-9]+)?' ...    % acq-<label>
            '(?<run>_run-[a-zA-Z0-9]+)?' ...    % run-<index>
            '_fieldmap\.nii(\.gz)?$'], 'names'); % NIfTI file extension
        if any(~cellfun(@isempty, labels))
            idx = find(~cellfun(@isempty, labels));
            for i = 1:numel(idx)
                fb = bids.internal.file_utils(bids.internal.file_utils(fileList{idx(i)}, 'basename'), 'basename');
                metafile = fullfile(pth, bids.internal.file_utils(fb, 'ext', 'json'));
                subject.fmap(j).type = 'fieldmap';
                subject.fmap(j).filename = fileList{idx(i)};
                subject.fmap(j).magnitude = strrep(fileList{idx(i)}, '_fieldmap.nii', '_magnitude.nii');
                subject.fmap(j).ses = regexprep(labels{idx(i)}.ses, '^_[a-zA-Z0-9]+-', '');
                subject.fmap(j).acq = regexprep(labels{idx(i)}.acq, '^_[a-zA-Z0-9]+-', '');
                subject.fmap(j).run = regexprep(labels{idx(i)}.run, '^_[a-zA-Z0-9]+-', '');
                if exist(metafile, 'file')
                    subject.fmap(j).meta = bids.util.jsondecode(metafile);
                else
                    % (!) TODO: file can also be stored at higher levels (inheritance principle)
                    subject.fmap(j).meta = struct([]); % ?
                end
                j = j + 1;
            end
        end
        
        % -Multiple phase encoded directions (topup)
        % ----------------------------------------------------------------------
        labels = regexp(fileList, [ ...
            '^sub-[a-zA-Z0-9]+' ...          % sub-<participant_label>
            '(?<ses>_ses-[a-zA-Z0-9]+)?' ... % ses-<label>
            '(?<acq>_acq-[a-zA-Z0-9]+)?' ... % acq-<label>
            '_dir-(?<dir>[a-zA-Z0-9]+)?' ... % dir-<index>
            '(?<run>_run-[a-zA-Z0-9]+)?' ... % run-<index>
            '_epi\.nii(\.gz)?$'], 'names');   % NIfTI file extension
        if any(~cellfun(@isempty, labels))
            idx = find(~cellfun(@isempty, labels));
            for i = 1:numel(idx)
                fb = bids.internal.file_utils(bids.internal.file_utils(fileList{idx(i)}, 'basename'), 'basename');
                metafile = fullfile(pth, bids.internal.file_utils(fb, 'ext', 'json'));
                subject.fmap(j).type = 'epi';
                subject.fmap(j).filename = fileList{idx(i)};
                subject.fmap(j).ses = regexprep(labels{idx(i)}.ses, '^_[a-zA-Z0-9]+-', '');
                subject.fmap(j).acq = regexprep(labels{idx(i)}.acq, '^_[a-zA-Z0-9]+-', '');
                subject.fmap(j).dir = labels{idx(i)}.dir;
                subject.fmap(j).run = regexprep(labels{idx(i)}.run, '^_[a-zA-Z0-9]+-', '');
                if exist(metafile, 'file')
                    subject.fmap(j).meta = bids.util.jsondecode(metafile);
                else
                    % (!) TODO: file can also be stored at higher levels (inheritance principle)
                    subject.fmap(j).meta = struct([]); % ?
                end
                j = j + 1;
            end
        end
    end
    
end

function subject = parse_eeg(subject)
    % --------------------------------------------------------------------------
    % -EEG data
    % --------------------------------------------------------------------------
    pth = fullfile(subject.path, 'eeg');
    if exist(pth, 'dir')
        
        % -EEG data file
        % ----------------------------------------------------------------------
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s.*_task-.*_eeg\\..*[^json]$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            % European data format (.edf)
            % BrainVision Core Data Format (.vhdr, .vmrk, .eeg) by Brain Products GmbH
            % The format used by the MATLAB toolbox EEGLAB (.set and .fdt files)
            % Biosemi data format (.bdf)
            
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task', 'acq', 'run', 'meta'});
            switch p.ext
                case {'.edf', '.vhdr', '.set', '.bdf'}
                    % each recording is described with a single file, even though the data can consist of multiple
                    subject.eeg = [subject.eeg p];
                    subject.eeg(end).meta = struct([]); % ?
                case {'.vmrk', '.eeg', '.fdt'}
                    % skip the additional files that come with certain data formats
                otherwise
                    % skip unknown files
            end
            
        end
        
        % -EEG events file
        % ----------------------------------------------------------------------
        % (!) TODO: events file can also be stored at higher levels (inheritance principle)
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s.*_task-.*_events\\.tsv$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task', 'acq', 'run', 'meta'});
            subject.eeg = [subject.eeg p];
            subject.eeg(end).meta = bids.util.tsvread(fullfile(pth, fileList{i})); % ?
            
        end
        
        % -Channel description table
        % ----------------------------------------------------------------------
        % (!) TODO: events file can also be stored at higher levels (inheritance principle)
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s.*_task-.*_channels\\.tsv$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task', 'acq', 'run', 'meta'});
            subject.eeg = [subject.eeg p];
            subject.eeg(end).meta = bids.util.tsvread(fullfile(pth, fileList{i})); % ?
            
        end
        
        % -Session-specific file
        % ----------------------------------------------------------------------
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s(_ses-[a-zA-Z0-9]+)?.*_(electrodes\\.tsv|photo\\.jpg|coordsystem\\.json|headshape\\..*)$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task', 'acq', 'run', 'meta'});
            subject.eeg = [subject.eeg p];
            subject.eeg(end).meta = struct([]); % ?
            
        end
        
    end
    
end

function subject = parse_meg(subject)
    % --------------------------------------------------------------------------
    % -MEG data
    % --------------------------------------------------------------------------
    pth = fullfile(subject.path, 'meg');
    if exist(pth, 'dir')
        
        % -MEG data file
        % ----------------------------------------------------------------------
        [fileList, d] = bids.internal.file_utils('List', pth, ...
            sprintf('^%s.*_task-.*_meg\\..*[^json]$', subject.name));
        if isempty(fileList)
            fileList = d;
        end
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task', 'acq', 'run', 'proc', 'meta'});
            subject.meg = [subject.meg p];
            subject.meg(end).meta = struct([]); % ?
            
        end
        
        % -MEG events file
        % ----------------------------------------------------------------------
        % (!) TODO: events file can also be stored at higher levels (inheritance principle)
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s.*_task-.*_events\\.tsv$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task', 'acq', 'run', 'proc', 'meta'});
            subject.meg = [subject.meg p];
            subject.meg(end).meta = bids.util.tsvread(fullfile(pth, fileList{i})); % ?
            
        end
        
        % -Channels description table
        % ----------------------------------------------------------------------
        % (!) TODO: channels file can also be stored at higher levels (inheritance principle)
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s.*_task-.*_channels\\.tsv$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task', 'acq', 'run', 'proc', 'meta'});
            subject.meg = [subject.meg p];
            subject.meg(end).meta = bids.util.tsvread(fullfile(pth, fileList{i})); % ?
            
        end
        
        % -Session-specific file
        % ----------------------------------------------------------------------
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s(_ses-[a-zA-Z0-9]+)?.*_(photo\\.jpg|coordsystem\\.json|headshape\\..*)$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task', 'acq', 'run', 'proc', 'meta'});
            subject.meg = [subject.meg p];
            subject.meg(end).meta = struct([]); % ?
            
        end
        
    end
    
end

function subject = parse_beh(subject)
    % --------------------------------------------------------------------------
    % -Behavioral experiments data
    % --------------------------------------------------------------------------
    pth = fullfile(subject.path, 'beh');
    if exist(pth, 'dir')
        fileList = bids.internal.file_utils('FPList', pth, ...
            sprintf('^%s.*_(events\\.tsv|beh\\.json|physio\\.tsv\\.gz|stim\\.tsv\\.gz)$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            % -Event timing, metadata, physiological and other continuous
            % recordings
            % ------------------------------------------------------------------
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task'});
            subject.beh = [subject.beh p];
            
        end
    end
end

function subject = parse_dwi(subject)
    % --------------------------------------------------------------------------
    % -Diffusion imaging data
    % --------------------------------------------------------------------------
    pth = fullfile(subject.path, 'dwi');
    if exist(pth, 'dir')
        fileList = bids.internal.file_utils('FPList', pth, ...
            sprintf('^%s.*_([a-zA-Z0-9]+){1}\\.nii(\\.gz)?$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            % -Diffusion imaging file
            % ------------------------------------------------------------------
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'acq', 'run', 'bval', 'bvec'});
            subject.dwi = [subject.dwi p];
            
            % -bval file
            % ------------------------------------------------------------------
            % bval file can also be stored at higher levels (inheritance principle)
            bvalfile = bids.internal.get_metadata(fileList{i}, '^.*%s\\.bval$');
            if isfield(bvalfile, 'filename')
                subject.dwi(end).bval = bids.util.tsvread(bvalfile.filename); % ?
            end
            
            % -bvec file
            % ------------------------------------------------------------------
            % bvec file can also be stored at higher levels (inheritance principle)
            bvecfile = bids.internal.get_metadata(fileList{i}, '^.*%s\\.bvec$');
            if isfield(bvalfile, 'filename')
                subject.dwi(end).bvec = bids.util.tsvread(bvecfile.filename); % ?
            end
            
        end
    end
end

function subject = parse_pet(subject)
    % --------------------------------------------------------------------------
    % -Positron Emission Tomography imaging data
    % --------------------------------------------------------------------------
    pth = fullfile(subject.path, 'pet');
    if exist(pth, 'dir')
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s.*_task-.*_pet\\.nii(\\.gz)?$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            % -PET imaging file
            % ------------------------------------------------------------------
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task', 'acq', 'rec', 'run'});
            subject.pet = [subject.pet p];
            
        end
    end
end

function subject = parse_ieeg(subject)
    % --------------------------------------------------------------------------
    % -Human intracranial electrophysiology
    % --------------------------------------------------------------------------
    pth = fullfile(subject.path, 'ieeg');
    if exist(pth, 'dir')
        
        % -iEEG data file
        % ----------------------------------------------------------------------
        fileList = bids.internal.file_utils('List', pth, ...
            sprintf('^%s.*_task-.*_ieeg\\..*[^json]$', subject.name));
        fileList = convert_to_cell(fileList);
        for i = 1:numel(fileList)
            
            % European Data Format (.edf)
            % BrainVision Core Data Format (.vhdr, .eeg, .vmrk) by Brain Products GmbH
            % The format used by the MATLAB toolbox EEGLAB (.set and .fdt files)
            % Neurodata Without Borders (.nwb)
            % MEF3 (.mef)
            
            p = bids.internal.parse_filename(fileList{i}, {'sub', 'ses', 'task', 'acq', 'run', 'meta'});
            switch p.ext
                case {'.edf', '.vhdr', '.set', '.nwb', '.mef'}
                    % each recording is described with a single file, even though the data can consist of multiple
                    subject.ieeg = [subject.ieeg p];
                    subject.ieeg(end).meta = struct([]); % ?
                case {'.vmrk', '.eeg', '.fdt'}
                    % skip the additional files that come with certain data formats
                otherwise
                    % skip unknown files
            end
            
        end

    end
end
