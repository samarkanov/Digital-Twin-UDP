% Script to generate C++ code, patch the main loop, and build the binary
% Detect model name (handles both original and exported versions)
if exist('udp_sine_gen_r2025b.slx', 'file')
    modelName = 'udp_sine_gen_r2025b';
else
    modelName = 'udp_sine_gen';
end
fprintf('Using model: %s\n', modelName);

% Define and create the build directory
% We assume this script is in projectRoot/matlab/
matlabScriptDir = fileparts(mfilename('fullpath'));
projectRoot = fileparts(matlabScriptDir);
bldDir = fullfile(projectRoot, 'bld');
if ~exist(bldDir, 'dir')
    mkdir(bldDir);
end

% Add current folder (matlab) to path to find the model and system object
addpath(matlabScriptDir);

% Load the model
load_system(modelName);

% 1. Redirect all build artifacts to the 'bld' folder
% Correct syntax for Simulink.fileGenControl
Simulink.fileGenControl('set', 'CacheFolder', bldDir, 'CodeGenFolder', bldDir);

% 2. Set the System Target File to Embedded Coder (ert.tlc)
set_param(modelName, 'SystemTargetFile', 'ert.tlc');
set_param(modelName, 'TargetLang', 'C++');
set_param(modelName, 'SolverType', 'Fixed-step');
set_param(modelName, 'Solver', 'FixedStepDiscrete');

% Use ConfigReader for fixed step size and pacing
addpath(fullfile(projectRoot, 'utils'));
cfg = ConfigReader();
sampleTime = cfg.getValue('sample_time');
pacingRate = cfg.getValue('pacing_rate');
set_param(modelName, 'FixedStep', num2str(sampleTime));
set_param(modelName, 'StopTime', '10'); % Finite stop time forces generation of the while loop

% Support variable-size signals (required for UDP Receive)
set_param(modelName, 'SupportVariableSizeSignals', 'on');

% 3. Configure code generation settings
set_param(modelName, 'MATLABDynamicMemAlloc', 'on');
set_param(modelName, 'GenerateSampleERTMain', 'on');
set_param(modelName, 'GenerateMakefile', 'on');
set_param(modelName, 'GenCodeOnly', 'on'); % Only generate code, don't build yet

% 4. Build the model (Generate code)
fprintf('Generating code for %s into %s...\n', modelName, bldDir);
rtwbuild(modelName);

% 5. Define build folder path (it's now inside bld/)
buildFolderName = [modelName '_ert_rtw'];
buildDirFull = fullfile(bldDir, buildFolderName);

    % 6. Patch the generated ert_main.cpp
    mainFile = fullfile(buildDirFull, 'ert_main.cpp');
    if exist(mainFile, 'file')
        fprintf('Patching %s with Indefinite Simulation Loop...\n', mainFile);
        content = fileread(mainFile);
        
        % 1. Ensure unistd.h is included for usleep
        if ~contains(content, '#include <unistd.h>')
            content = strrep(content, ['#include "' modelName '.h"'], ...
                sprintf('#include "%s.h"\n#include <unistd.h>', modelName));
        end
        
        % 2. Define our custom main body with exception handling
        usleepDelay = round((sampleTime / pacingRate) * 1000000);
        modelObjName = [modelName '_Obj'];
        
        customMainBody = [ ...
            '  (void)(argc);' newline ...
            '  (void)(argv);' newline ...
            '  try {' newline ...
            '    ' modelObjName '.initialize();' newline ...
            '    printf("Simulation started (Pacing: ' num2str(pacingRate) 'x)...\\n");' newline ...
            '    while (' modelObjName '.getRTM()->getErrorStatus() == (nullptr)) {' newline ...
            '      rt_OneStep();' newline ...
            '      usleep(' num2str(usleepDelay) ');' newline ...
            '    }' newline ...
            '    ' modelObjName '.terminate();' newline ...
            '  } catch (const std::exception& e) {' newline ...
            '    fprintf(stderr, "C++ Exception caught: %s\\n", e.what());' newline ...
            '    return 1;' newline ...
            '  } catch (...) {' newline ...
            '    fprintf(stderr, "Unknown C++ Exception caught!\\n");' newline ...
            '    return 1;' newline ...
            '  }' newline ...
            '  return 0;' ...
        ];

        % 3. Replace the entire content between the first { and the last } of the main function
        % This regex finds int main(...) { <EVERYTHING> }
        mainRegex = '(int_T main\(int_T argc, const char \*argv\[\]\)\s*\{)(.*)(\})';
        content = regexprep(content, mainRegex, ['$1' newline customMainBody newline '$3']);
        
        % Ensure <exception> is included
        if ~contains(content, '#include <exception>')
             content = strrep(content, '#include <unistd.h>', sprintf('#include <unistd.h>\n#include <exception>'));
        end
        
        % Write the patched content back
        fid = fopen(mainFile, 'w');
        fprintf(fid, '%s', content);
        fclose(fid);
        
        fprintf('Successfully forced simulation loop into ert_main.cpp\n');
        
    % Strip absolute host paths from all generated .cpp and .h files
    % This is crucial because Simulink often hardcodes dlopen paths like
    % "/home/user/.../libmwudpdevice.so" which breaks in Docker.
    fprintf('Stripping absolute host paths from generated source files...\n');
    srcFiles = dir(fullfile(buildDirFull, '*.cpp'));
    hdrFiles = dir(fullfile(buildDirFull, '*.h'));
    allSrcFiles = [srcFiles; hdrFiles];
    
    for k = 1:length(allSrcFiles)
        fPath = fullfile(allSrcFiles(k).folder, allSrcFiles(k).name);
        fileData = fileread(fPath);
        
        % Match "/any/path/to/LibraryName.so" or similar and replace with "LibraryName.so"
        % Specifically targeting paths containing 'toolbox' or 'bin/glnxa64'
        modifiedData = regexprep(fileData, '"/[^"]*/(libmw[^/"]+|testcoderconverterarrays[^/"]*)"', '"$1"');
        
        if ~strcmp(fileData, modifiedData)
            fid = fopen(fPath, 'w');
            fprintf(fid, '%s', modifiedData);
            fclose(fid);
            fprintf('  Patched absolute paths in %s\n', allSrcFiles(k).name);
        end
    end
    
    % 7. Re-run the build to compile the patched main
    fprintf('Re-building with patched main...\n');
    cd(buildDirFull);
    
    % Force rebuild by deleting the binary if it exists
    binaryNameInBuild = fullfile(buildDirFull, modelName);
    if exist(binaryNameInBuild, 'file'), delete(binaryNameInBuild); end
    
    % Use ConfigReader to get MATLAB library path
    addpath(fullfile(projectRoot, 'utils'));
    cfg = ConfigReader();
    
    % Robustly get library path inside Docker or Local
    matlabLibPath = '';
    if ~isempty(getenv('MATLAB_INSTALL_LOCATION'))
        matlabLibPath = fullfile(getenv('MATLAB_INSTALL_LOCATION'), 'bin', 'glnxa64');
    else
        try
            matlabLibPath = cfg.getLibraryPath();
        catch
            matlabLibPath = '/usr/local/matlab/bin/glnxa64';
        end
    end
    
    fprintf('Building with MATLAB library path: %s\n', matlabLibPath);
    
    % Build the binary without baking in an absolute RPATH.
    makeCmd = sprintf('make -f %s.mk CPP_WARN_FLAGS="-Wno-write-strings"', modelName);
    
    [status, cmdOut] = system(makeCmd);
    cd(projectRoot);
    
    if status == 0
        fprintf('Build successful!\n');
        
        % The binary is usually created in the folder above the build folder
        binaryPath = fullfile(bldDir, modelName);
        if exist(binaryPath, 'file')
            fprintf('Binary is ready at: %s\n', binaryPath);
            
            % REPAIR STEP: Dynamically find and strip absolute paths
            fprintf('Repairing binary: identifying absolute library dependencies...\n');
            [lddStat, lddRaw] = system(sprintf('export PATH=/usr/bin:/bin:$PATH && ldd %s', binaryPath));
            if lddStat == 0
                % Find paths that start with / but are NOT in standard system locations
                absLibs = regexp(lddRaw, '(/[^ ]+libmwasynciocoder\.so[^ ]*)', 'match');
                if ~isempty(absLibs)
                    absPath = absLibs{1};
                    fprintf('Found absolute dependency: %s\n', absPath);
                    relPath = 'libmwasynciocoder.so';
                    
                    % Pad with nulls to maintain string length
                    paddingCount = length(absPath) - length(relPath);
                    nulls = repmat('00', 1, paddingCount);
                    
                    absHex = sprintf('%02X', uint8(absPath));
                    relHex = [sprintf('%02X', uint8(relPath)) nulls];
                    
                    repairCmd = sprintf('hexdump -ve ''1/1 "%%02X"'' %s | sed "s/%s/%s/g" | xxd -r -p > %s.tmp && mv %s.tmp %s', ...
                        binaryPath, absHex, relHex, binaryPath, binaryPath, binaryPath);
                    
                    [repStatus, repOut] = system(repairCmd);
                    if repStatus == 0
                        system(sprintf('chmod +x %s', binaryPath));
                        fprintf('Successfully repaired: %s -> %s\n', absPath, relPath);
                    else
                        fprintf('Binary repair failed: %s\n', repOut);
                    end
                else
                    fprintf('No absolute MATLAB dependencies found to repair.\n');
                end
            end
        else
            fprintf('Warning: Binary not found at %s for repair.\n', binaryPath);
        end
        
        % Create bld/libs directory and gather dependencies
        libDir = fullfile(bldDir, 'libs');
        if exist(libDir, 'dir'), system(sprintf('rm -rf "%s"', libDir)); end
        mkdir(libDir);
        
        % Explicitly copy the asyncIO library
        asyncIoPath = fullfile(matlabLibPath, 'libmwasynciocoder.so');
        if exist(asyncIoPath, 'file')
            copyfile(asyncIoPath, libDir, 'f');
            fprintf('Explicitly copied: %s\n', asyncIoPath);
        end
        
        % Explicitly copy dynamically loaded UDP libraries from the toolbox
        matlabRootPath = fileparts(fileparts(matlabLibPath));
        networkLibBinPath = fullfile(matlabRootPath, 'toolbox', 'shared', 'networklib', 'bin', 'glnxa64');
        
        udpDevicePath = fullfile(networkLibBinPath, 'libmwudpdevice.so');
        if exist(udpDevicePath, 'file')
            copyfile(udpDevicePath, libDir, 'f');
            fprintf('Explicitly copied: %s\n', udpDevicePath);
        end
        
        networkCoderPath = fullfile(networkLibBinPath, 'libmwnetworkcoderconverter.so');
        if exist(networkCoderPath, 'file')
            copyfile(networkCoderPath, libDir, 'f');
            fprintf('Explicitly copied: %s\n', networkCoderPath);
        end
        
        testCoderPath = fullfile(matlabRootPath, 'toolbox', 'shared', 'asynciolib', 'bin', 'glnxa64', 'libmwtestcoderconverterarrays.so');
        if exist(testCoderPath, 'file')
            copyfile(testCoderPath, libDir, 'f');
            fprintf('Explicitly copied: %s\n', testCoderPath);
        end
        
        bufferPath = fullfile(matlabRootPath, 'toolbox', 'shared', 'testmeaslib', 'general', 'bin', 'glnxa64', 'libmwbuffer.so');
        if exist(bufferPath, 'file')
            copyfile(bufferPath, libDir, 'f');
            fprintf('Explicitly copied: %s\n', bufferPath);
        end
        
        networkSupportPath = fullfile(matlabRootPath, 'toolbox', 'shared', 'networklib', 'bin', 'glnxa64', 'libmwnetworksupport.so');
        if exist(networkSupportPath, 'file')
            copyfile(networkSupportPath, libDir, 'f');
            fprintf('Explicitly copied: %s\n', networkSupportPath);
        end
        
        fprintf('Gathering shared library dependencies recursively...\n');

        % Use a loop to gather all dependencies from binary and all libraries in libDir
        % This handles the case where libraries depend on other libraries
        allGathered = false;
        while ~allGathered
            allGathered = true;

            % Check dependencies of the binary and all libs already in libDir
            d = dir(fullfile(libDir, '*.so*'));
            searchTargets = [ {binaryPath}; fullfile(libDir, {d.name})' ];

            for j = 1:length(searchTargets)
                target = searchTargets{j};
                if isempty(target), continue; end

                [status, lddOut] = system(sprintf('export PATH=/usr/bin:/bin:$PATH && ldd "%s"', target));
                if status ~= 0, continue; end

                tokens = regexp(lddOut, '(/[^\s]+\.so[^\s]*)', 'tokens');
                if isempty(tokens), continue; end
                uniqueLibs = unique([tokens{:}]);

                for i = 1:length(uniqueLibs)
                    lPath = strtrim(uniqueLibs{i});
                    [~, lName, lExt] = fileparts(lPath);

                    % Skip virtual, non-existent, and CORE system libraries
                    % core system libs are better provided by the target OS/Docker image
                    coreSystemLibs = {'libc', 'libm', 'libpthread', 'libdl', 'librt', 'ld-linux-x86-64', 'libgcc_s', 'libstdc++', 'libresolv'};
                    isCore = false;
                    for k = 1:length(coreSystemLibs)
                        % We check for exact match or starting with the name followed by a dot or dash
                        if strcmp(lName, coreSystemLibs{k}) || ...
                           startsWith(lName, [coreSystemLibs{k} '.']) || ...
                           startsWith(lName, [coreSystemLibs{k} '-'])
                            isCore = true;
                            break;
                        end
                    end

                    if contains(lName, 'linux-vdso', 'IgnoreCase', true) || ~exist(lPath, 'file') || isCore
                        continue;
                    end

                    destFile = fullfile(libDir, [lName lExt]);
                    if ~exist(destFile, 'file')
                        copyfile(lPath, libDir, 'f');
                        fileattrib(destFile, '+w');
                        fprintf('  Copied dependency: %s%s\n', lName, lExt);
                        allGathered = false; % Found a new one, need another pass
                    end
                end
            end
        end
        fprintf('Successfully gathered all dependencies into %s\n', libDir);    else
        fprintf('Build failed with error:\n%s\n', cmdOut);
    end
else
    fprintf('Error: %s not found.\n', mainFile);
end

% Close the model without saving changes
if bdIsLoaded(modelName), close_system(modelName, 0); end
