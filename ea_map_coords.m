function [XYZ_dest_mm, XYZ_dest_vx] = ea_map_coords(varargin)
% Coordinates mapping, support SPM, ANTs and FSL linear and non-linear
% transformation.
%
% Please use this function for any point transform within the Lead Suite
% environment. It should automatically detect whether to use ANTs, SPM or
% FSL based transforms for the respective subject.
%
% Parameters:
%     XYZ_src_vx: coordinates to be transformed, size: 3*N or 4*N
%     src: the image defining the space of the src coordinates
%     transform: transformation from src image to dest image, optional
%     dest: the image defining the space of the dest coordinates, optional
%     transformmethod: the transformation method used, case insensitive, optional
%
%     useinverse: use the inverse of the transformation or not, only needed
%                 by ANTs in the manual mode (calling outside LEAD with
%                 explicitly specified transformation file), optional
%
% Output:
%     XYZ_dest_mm: mm coordinates in dest image. size: 3*N
%     XYZ_dest_vx: vox coordinates in dest image. size: 3*N
%
% To map the 'vox' coords in src to the 'mm' coords in src:
%     XYZ_mm = ea_map_coords(XYZ_vx, src);
%
% To map the 'mm' coords in src to the 'vox' coords in src:
%     [~, XYZ_vox] = ea_map_coords(XYZ_mm, src);
%
% To map the 'vox' coords in src to the 'mm' coords in dest:
%     XYZ_dest_mm = ea_map_coords(XYZ_src_vx, src, transform);
%
% To map the 'vox' coords in src to the 'mm' coords in dest, LEAD pipeline:
%     XYZ_dest_mm = ea_map_coords(XYZ_vx, src, 'SUBJECT_PATH/y_ea_inv_normparams.nii', dest);
%
% To map the 'vox' coords in src to the 'mm' coords in dest with transformmethod applied:
%     XYZ_dest_mm = ea_map_coords(XYZ_vx, src, transform, dest, transformmethod);
%
% 'transform' is the tranformation generated by registrating src to dest
% (can also use the inverse transformation in some cases like ANTs or FLIRT)
% It can be:
%     4*4 affine matrix (vox to mm affine)
%
%     4*4 affine matrix as mat file (vox to mm affine)
%     transformmethod: 'AFFINE'
%
%     1*N transformation from spm_coreg(dest, src)
%
%     1*N transformation as mat file from spm_coreg(dest, src)
%     transformmethod: 'COREG'
%
%     '*.mat' file from SPM coreg.estwrite (vox to mm affine), check ea_spm_coreg
%     transformmethod: 'SPM'
%
%     '*.mat' file from ANTs (Linear) (mm to mm affine), check ea_ants
%     transformmethod: 'ANTS'
%
%     '*.mat' file from FSL (FLIRT) (mm to mm afine), check ea_flirt
%     transformmethod: 'FSL' or 'FLIRT'
%
%     old '*_sn.mat' file from SPM (DCT structure)
%
%     'y_ea_normparams.nii' or 'y_ea_inv_normparams.nii' file form LEAD.In
%     this case, real transformation file for SPM, ANTs or FSL will be
%     automatically dected (in the subject's folder), i.e., even if the
%     registration was dne with ANTs, you can still specify the transform
%     as one of these two, the code will handle it acordingly. Thus you can
%     use an unified calling to do the mapping, no need to check the
%     normalization method beforehand. Check the comments below for more
%     informations.
%
%     'y_*.nii' or 'iy_*.nii' file from SPM
%
%     '*.nii', '*.nii.gz' or '*.h5' file from ANTs (Non-linear)
%     transformmethod: 'ANTS'
%
%     '*.nii' or '*.nii.gz' files from FNIRT
%     transformmethod: 'FSL' or 'FNIRT'
%
% For SPM and ANTs, to map the coords in src image to the coords in dest
% image (the registration was done using src image as moving image and dest
% image as fixed image), the INVERSE version of the transformation should
% be used.
%
% For FSL, to map the coords in src image to the coords in dest image
% (still, the registration was done using src image as moving image and
% dest image as fixed image), the direct warp field is used as in the
% official document. But this way has severe performance issue since it
% internally inverts the warp field for each point in each iteration. To
% solve this problem, here we make a modified version of 'img2imgcoord',
% which can also use the inverse version of the warp filed. Thus the coords
% mapping is extremely speeded up. So it is recommended here to use the
% inverse version of the warp field if you want to do the coords mapping
% manually.
%
% If the registration was done by ANTs, and you want to manually do the
% coords mapping (outside the LEAD environment):
%    XYZ_dest_mm = ea_map_coords(XYZ_src_vx, src, transform, dest, 'ANTS');
% The 'tranform' here should be the deformation field file generated by
% registering src to dest (not the inverse one), 'useinverse' is set to 1
% by default. Set 'useinverse' only if you really know what you are doing.


if nargin < 2
    error('Must specify at least coords and src!')
end

XYZ_src_vx=varargin{1};

src=varargin{2};

if nargin >= 3
    transform=varargin{3};
end

if nargin >= 4
    dest=varargin{4};
end

% Check input coordinates, XYZ_vx should be column vector: 3*N or 4*N
if size(XYZ_src_vx, 1) == 3
    % make homogeneous
    XYZ_src_vx = [XYZ_src_vx; ones(1,size(XYZ_src_vx, 2))];
elseif size(XYZ_src_vx, 1) ~= 4
    error('Coord array must have 3 or 4 rows: [x;y;z] or [x;y;z;1]')
end

% srcvx to/from srcmm only
if nargin == 2
    if nargout == 1
        XYZ_dest_mm = spm_get_space(src) * XYZ_src_vx;
    elseif nargout == 2
        % if input coords are actually in world space, then output the
        % voxel space
        XYZ_dest_mm = varargin{1};
        dest = src;
        XYZ_dest_vx = spm_get_space(dest) \ XYZ_dest_mm;
        XYZ_dest_vx=XYZ_dest_vx(1:3,:);
    end
    XYZ_dest_mm=XYZ_dest_mm(1:3,:);
    transform = []; % finish mapping, set to empty
end

% transformation specified
if ~isempty(transform)

    % transformation is a variable, LINEAR case
    if ~ischar(transform)

        if isequal(size(transform),[4 4]) % 4*4 affine matrix supplied
            XYZ_dest_mm = transform * XYZ_src_vx;

        elseif size(transform,1) == 1 % 1*N return value from spm_coreg(dest, src) suppplied
            XYZ_dest_mm = spm_matrix(transform(:)')\spm_get_space(src)*XYZ_src_vx;

        else
            error('Improper or unsuported transform specified!');
        end

    % DCT structure from old SPM code, NON-LINEAR case
    elseif ~isempty(regexp(transform, 'sn\.mat$', 'once'))

        % DCT sn structure
        XYZ_dest_mm = srcvx2destmm_sn(XYZ_src_vx, transform);

    % mat file supplied, LINEAR case
    elseif ~isempty(regexp(transform, '\.mat$', 'once'))

        % Need to differentiate  the transformation type
        if nargin >= 5
            transformmethod = varargin{5};
        else
            transformmethod = 'FALLBACK';
        end

        transformmethod = strsplit(transformmethod, ' '); % compatible with 'options.coregmr.method'
        transformmethod = upper(transformmethod{end});

        switch transformmethod

            case {'AFFINE'} % file is  4*4 affine matrix
                transform = load(transform);
                varname = fieldnames(transform);
                transform = transform.(varname{1});
                XYZ_dest_mm = transform * XYZ_src_vx;

            case {'COREG'} % file is 1*N spm_coreg return value
                transform = load(transform);
                varname = fieldnames(transform);
                transform = transform.(varname{1});
                XYZ_dest_mm = spm_matrix(transform(:)')\spm_get_space(src)*XYZ_src_vx;

            case {'SPM'} % Registration done by SPM (ea_spm_coreg)
                % fuzzy match, transform can be specified as XX2XX_spm.mat
                % or simply XX2XX.mat
                if ~strcmp(transform(end-7:end), '_spm.mat')
                    transform = [transform(1:end-4), '_spm.mat'];
                end
                transform = load(transform, 'spmaffine');
                transform = transform.spmaffine;
                XYZ_dest_mm = transform * XYZ_src_vx;

            case {'ANTS'} % Registration done by ANTs (ea_ants)
                directory = fileparts(transform);
                if isempty(directory)
                    directory = '.';
                end

                % fuzzy match, transform can be specified as
                % XX2XX_antsX.mat, XX2XX_ants.mat or simply XX2XX.mat
                if regexp(transform,'_ants\d*\.mat$', 'once')
                    transform = transform(1:regexp(transform,'_ants\d*\.mat$', 'once')-1);
                else
                    transform = transform(1:end-4);
                end

                % check transformation file
                match = dir([transform, '_ants*.mat']);
                matchdirect=dir([transform,'.mat']);
                if ~isempty(matchdirect) % specific ANTs transform file has been given
                    transform=[transform,'.mat'];
                    useinverse=1;
                else
                    if ~isempty(match) % src2dest.mat exists
                        transform = [directory, filesep, match(end).name];
                        useinverse = 1; % Registration was done from src to dest, so we need to use inverse here
                    else % if src2dest.mat is not found, check if dest2src.mat exists
                        [~, transformname] = fileparts(transform);
                        imgname = strsplit(transformname, '2');
                        transform = [directory, filesep, imgname{2}, '2', imgname{1}];
                        match = dir([transform, '_ants*.mat']);
                        transform = [directory, filesep, match(end).name];
                        useinverse = 0; % Registration was done from dest to src, no inverse needed
                    end
                end

                % vox to mm, ANTs takes mm coords as input
                XYZ_src_mm = spm_get_space(src)*XYZ_src_vx;

                % RAS to LPS, ANTs (ITK) use LPS coords
                XYZ_src_mm(1,:)=-XYZ_src_mm(1,:);
                XYZ_src_mm(2,:)=-XYZ_src_mm(2,:);

                % apply transform, need transpose becuase ANTs prefer N*3
                % like row vector
                XYZ_dest_mm = ea_ants_apply_transforms_to_points(directory, XYZ_src_mm(1:3,:)', useinverse, transform)';

                % LPS to RAS, restore to RAS coords
                XYZ_dest_mm(1,:)=-XYZ_dest_mm(1,:);
                XYZ_dest_mm(2,:)=-XYZ_dest_mm(2,:);

                %  make sure coors is in 4*N size (for further transformation)
                XYZ_dest_mm = [XYZ_dest_mm; ones(1,size(XYZ_dest_mm, 2))];

            case {'FSL', 'FLIRT','FSL FLIRT','FSL BBR'} % Registration done by FSL (ea_flirt)
                directory = fileparts(transform);
                if isempty(directory)
                    directory = '.';
                end

                % fuzzy match, transform can be specified as
                % XX2XX_flirtX.mat, XX2XX_flirt.mat or simply XX2XX.mat
                if regexp(transform,'_flirt\d*\.mat$', 'once')
                    transform = transform(1:regexp(transform,'_flirt\d*\.mat$', 'once')-1);
                else
                    transform = transform(1:end-4);
                end
                match = dir([transform, '_flirt*.mat']);
                transform = [directory, filesep, match(end).name];

                % vox to mm, use img2imgcoord to do mm coords
                % transformation
                XYZ_src_mm = spm_get_space(src)*XYZ_src_vx;

                % apply transform, need transpose because FSL prefer N*3
                % like row vector
                XYZ_dest_mm = ea_fsl_img2imgcoord(XYZ_src_mm(1:3,:)', src, dest, transform, 'l')';

                %  make sure coors is in 4*N size (for further transformation)
                XYZ_dest_mm = [XYZ_dest_mm; ones(1,size(XYZ_dest_mm, 2))];

            otherwise % actual FALLBACK
                % If no transformmethod is supplied, do a just-in-time
                % spm_coreg here as fallback, since linear transformation
                % is not computational expensive anyway, the transformation
                % will be saved as {$src}2{$dest}.mat
                fprintf('\nTransformation method not found!\nFallback to spm_coreg...\n');
                x = spm_coreg(dest, src);
                XYZ_dest_mm = spm_matrix(x(:)')\spm_get_space(src)*XYZ_src_vx;

                directory = fileparts(src);
                if isempty(directory)
                    directory = '.';
                end
                [~, mov] = ea_niifileparts(src);
                [~, fix] = ea_niifileparts(dest);
                save([directory, filesep, mov, '2', fix, '.mat'], 'x');
        end

   	% 'y_ea_normparams.nii' or 'y_ea_inv_normparams.nii' supplied, LEAD's
   	% non-linear case, proper tranformation files will be automatically
    % detected for ANTs and FSL. 'y_ea_inv_normparams.nii' should be used
    % if you want to map src coords to dest coords (internally, for SPM,
    % ANTs and FSL, the inverse of the deformation field is used for the
    % mapping). NOLINEAR case.
    elseif ~isempty(regexp(transform, 'y_ea_.*normparams\.nii$', 'once'))

        % check which normalization method has been used
    	directory = fileparts(transform);
        if isempty(directory)
            directory = '.';
        end
        transformmethod=ea_whichnormmethod(directory);

        switch transformmethod

            case ea_getantsnormfuns % ANTs (ea_ants_nolinear) used in LEAD
                if ~isempty(strfind(transform, 'y_ea_inv_normparams.nii'))
                    useinverse = 1;
                else
                    useinverse = 0;
                end

                % vox to mm, ANTs takes mm coords as input
                V=ea_open_vol(src); % .gz support, dont use spm_get_space here.
                XYZ_src_mm = V.mat*XYZ_src_vx;

                % RAS to LPS, ANTs (ITK) use LPS coords
                XYZ_src_mm(1,:)=-XYZ_src_mm(1,:);
                XYZ_src_mm(2,:)=-XYZ_src_mm(2,:);

                % apply transform, need transpose becuase ANTs prefer N*3
                % like row vector
                XYZ_dest_mm=ea_ants_apply_transforms_to_points(directory,XYZ_src_mm(1:3,:)',useinverse)';

                % LPS to RAS, restore to RAS coords
                XYZ_dest_mm(1,:)=-XYZ_dest_mm(1,:);
                XYZ_dest_mm(2,:)=-XYZ_dest_mm(2,:);

                %  make sure coors is in 4*N size (for further transformation)
                XYZ_dest_mm = [XYZ_dest_mm; ones(1,size(XYZ_dest_mm, 2))];

            case ea_getfslnormfuns % FSL (ea_fnirt) used in lead
                % if 'y_ea_inv_normparams.nii' is specified, it means
                % mapping from src coords to dest coords, i.e., NOT the
                % inverse mapping (from dest coords to src coords).
                if ~isempty(strfind(transform, 'y_ea_inv_normparams.nii'))
                    inversemap = 0;
                else
                    inversemap = 1;
                end

                % vox to mm, use img2imgcoord to do mm coords
                % transformation
                XYZ_src_mm = spm_get_space(src)*XYZ_src_vx;

                % apply transform, need transpose because FSL prefer N*3
                % like row vector
                XYZ_dest_mm = ea_fsl_apply_normalization_to_points(directory,XYZ_src_mm(1:3,:)',inversemap)';

                %  make sure coors is in 4*N size (for further transformation)
                XYZ_dest_mm = [XYZ_dest_mm; ones(1,size(XYZ_dest_mm, 2))];

            % Default use SPM to do the mapping, 'y_ea_normparams.nii' or
            % 'y_ea_inv_normparams.nii' file really exists (was generated
            % by SPM)
            otherwise
                XYZ_dest_mm = srcvx2destmm_deform(XYZ_src_vx, transform);
        end

    % 'y_*.nii' or 'iy_*.nii' from SPM supplied, NOLINEAR case
    elseif ~isempty(regexp(transform, 'y_.*\.nii$', 'once'))
        XYZ_dest_mm = srcvx2destmm_deform(XYZ_src_vx, transform);

    % '*.nii', '*.nii.gz' or '*.h5' files (from ANTs or FSL) supplied, NOLINEAR case
    elseif ~isempty(regexp(transform, '\.nii$', 'once')) || ... % ANTs or FSL naming
           ~isempty(regexp(transform, '\.nii.gz$', 'once')) || ... % ANTs or FSL naming
           ~isempty(regexp(transform, '\.h5$', 'once')) % ANTs naming

        % Need to specify the transformation type
        if nargin >= 5
            transformmethod = varargin{5};
            transformmethod = upper(transformmethod);
        else
            error('Please specify the transformation type');
        end

        switch transformmethod

            case {'ANTS'} % ANTs used
                if nargin >= 6
                    useinverse = varargin{6};
                else
                    useinverse = 0; % suppose proper deformation field specified, no need to invert
                end

                directory = fileparts(transform);
                if isempty(directory)
                    directory = '.';
                end

                % vox to mm, ANTs takes mm coords as input
                XYZ_src_mm = spm_get_space(src)*XYZ_src_vx;

                % RAS to LPS, ANTs (ITK) use LPS coords
                XYZ_src_mm(1,:)=-XYZ_src_mm(1,:);
                XYZ_src_mm(2,:)=-XYZ_src_mm(2,:);

                % apply transform, need transpose becuase ANTs prefer N*3
                % like row vector
                XYZ_dest_mm=ea_ants_apply_transforms_to_points(directory, XYZ_src_mm(1:3,:)', useinverse, transform)';

                % LPS to RAS, restore to RAS coords
                XYZ_dest_mm(1,:)=-XYZ_dest_mm(1,:);
                XYZ_dest_mm(2,:)=-XYZ_dest_mm(2,:);

                %  make sure coors is in 4*N size (for further transformation)
                XYZ_dest_mm = [XYZ_dest_mm; ones(1,size(XYZ_dest_mm, 2))];

            case {'FSL', 'FNIRT'} % FSL (ea_fnirt) used
                % vox to mm, use img2imgcoord to do mm coords
                % transformation
                XYZ_src_mm = spm_get_space(src)*XYZ_src_vx;

                % apply transform, need transpose because FSL prefer N*3
                % like row vector
                XYZ_dest_mm = ea_fsl_img2imgcoord(XYZ_src_mm(1:3,:)', src, dest, transform, 'n')';

                %  make sure coors is in 4*N size (for further transformation)
                XYZ_dest_mm = [XYZ_dest_mm; ones(1,size(XYZ_dest_mm, 2))];

            otherwise
                error(['Unsupported transformation type: ', transformmethod])
        end

    else
        error(['Unsupported transformation file:\n', transform])
    end

    % Optional output from dest vx coords
    if nargout == 2
        if nargin >= 4 % dest image specified
            XYZ_dest_vx = spm_get_space(dest) \ XYZ_dest_mm;

        elseif ~isempty(regexp(transform, 'sn\.mat$', 'once')) % transform is SPM DCT file
            sn = load(transform, 'VF');
            XYZ_dest_vx = sn.VF.mat \ XYZ_dest_mm;

        elseif ~isempty(regexp(transform, '_spm\.mat$', 'once')) % transform is from ea_spm_coreg
            affine = load(transform, 'fixed');
            XYZ_dest_vx = affine.fixed \ XYZ_dest_mm;
        end

        XYZ_dest_vx=XYZ_dest_vx(1:3,:);
    end

    XYZ_dest_mm=XYZ_dest_mm(1:3,:);
end


function coord = srcvx2destmm_sn(coord, matname)
% returns mm coordinates based on the old version of the SPM tranformation:
% '*_sn.mat'

sn = load(matname);
Tr = sn.Tr;

if numel(Tr) ~= 0 % DCT warp: src_vox displacement
    d = sn.VG(1).dim(1:3); % (since VG may be 3-vector of TPM volumes)
    dTr = size(Tr);
    basX = spm_dctmtx(d(1), dTr(1), coord(1,:)-1);
    basY = spm_dctmtx(d(2), dTr(2), coord(2,:)-1);
    basZ = spm_dctmtx(d(3), dTr(3), coord(3,:)-1);
    for i = 1:size(coord, 2)
        bx = basX(i, :);
        by = basY(i, :);
        bz = basZ(i, :);
        tx = reshape(...
            reshape(Tr(:,:,:,1),dTr(1)*dTr(2),dTr(3))*bz',dTr(1),dTr(2) );
        ty = reshape(...
            reshape(Tr(:,:,:,2),dTr(1)*dTr(2),dTr(3))*bz',dTr(1),dTr(2) );
        tz =  reshape(...
            reshape(Tr(:,:,:,3),dTr(1)*dTr(2),dTr(3))*bz',dTr(1),dTr(2) );
        coord(1:3,i) = coord(1:3,i) + [bx*tx*by' ; bx*ty*by' ; bx*tz*by'];
    end
end

% Affine: src_vx (possibly displaced by above DCT) to dest_vx
coord = sn.VF.mat * sn.Affine * coord;


function dest_mm = srcvx2destmm_deform(src_vx, deform)
% returns mm coordinates based on deformation field file 'y_*.nii' from src
% image to dest image

if ischar(deform)
    deform = spm_vol([repmat(deform,3,1),[',1,1';',1,2';',1,3']]);
end

src_vx = double(src_vx);
dest_mm = [spm_sample_vol(deform(1,:),src_vx(1,:),src_vx(2,:),src_vx(3,:),1);...
          spm_sample_vol(deform(2,:),src_vx(1,:),src_vx(2,:),src_vx(3,:),1);...
          spm_sample_vol(deform(3,:),src_vx(1,:),src_vx(2,:),src_vx(3,:),1)];
if size(src_vx,1) == 4
    dest_mm = [dest_mm; src_vx(4,:)];
end


